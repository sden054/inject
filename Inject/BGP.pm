# Set package
package Inject::BGP;

# Version
$VERSION = $Inject::VERSION;

# Modules
use warnings;
use strict;
use base 'Inject';
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use Inject::Utils;
use Data::Dumper;
use Net::BGP::ASPath;
use Net::BGP::NLRI qw/:origin/;
use Net::BGP::Peer;
use Net::BGP::Process;
use Net::BGP::Update;
use Net::BGP::Transport;
use threads;
use threads::shared;

require Exporter;

@ISA = qw(Exporter AutoLoader);

@EXPORT = qw();
our %EXPORT_TAGS = (
	'all' => [ qw(
		 ) ]
);


# Globals
our $PEERS = ();

# Make aliases for variables
our $DEBUG = ();
*DEBUG = *Inject::DEBUG;

our $PEER_INFO = ();
*PEER_INFO = *Inject::PEER_INFO;

our $ROUTES_IN = ();
*ROUTES_IN = *Inject::ROUTES_IN;

our $ROUTES_OUT = ();
*ROUTES_OUT = *Inject::ROUTES_OUT;


# Constants
my @BGP_ERROR_CODE = qw(
	NULL
	MESSAGE_HEADER
	OPEN_MESSAGE
	UPDATE_MESSAGE
	HOLD_TIMER_EXPIRED
	FINITE_STATE_MACHINE
	CEASE
);

my @BGP_SUB_ERROR_CODE_MSG = qw(
	NULL
	CONNECTION_NOT_SYNC
	BAD_MESSAGE_LENGTH
	BAD_MESSAGE_TYPE
);

my @BGP_SUB_ERROR_CODE_OPEN = qw(
	NULL
	BAD_VERSION_NUM
	BAD_PEER_AS
	BAD_BGP_ID
	BAD_OPT_PARAMETER
	AUTH_FAILURE
	BAD_HOLD_TIME
);

my @BGP_SUB_ERROR_CODE_UPDATE = qw(
	NULL
	MALFORMED_ATTR_LIST
	BAD_WELL_KNOWN_ATTR
	MISSING_WELL_KNOWN_ATTR
	BAD_ATTR_FLAGS
	BAD_ATTR_LENGTH
	BAD_ORIGIN_ATTR
	AS_ROUTING_LOOP
	BAD_NEXT_HOP_ATTR
	BAD_OPT_ATTR
	BAD_NLRI
	BAD_AS_PATH
);


my @BGP_SUB_ERROR_CODE_CEASE = qw(
	NULL
	MAX_NUM_PREF
	ADMIN_SHUTDOWN
	PEER_DECONFIGURED
	ADMIN_RESET
	CONNECTION_REJECT
	OTHER_CONFIG_CHANGE
	CONNECTION_COLLISION_RESOLUTION
	OUT_OF_RESOURCES
);


# Function bgp_t
sub bgp_t {
	# BGP object
	my $bgp = Net::BGP::Process->new();

	# Add BGP peers
	foreach (keys %{$Inject::CONFIG->{peer}}) {
		$PEERS->{$_} = Net::BGP::Peer->new(
			ThisID 	=> $Inject::CONFIG->{local}->{address},
			ThisAS 	=> $Inject::CONFIG->{local}->{as},
			PeerID 	=> $Inject::CONFIG->{peer}->{$_}->{address},
			PeerAS 	=> $Inject::CONFIG->{peer}->{$_}->{as},
			PeerPort => ($Inject::CONFIG->{peer}->{$_}->{port}?$Inject::CONFIG->{peer}->{$_}->{port}:179),
			Listen => ($Inject::CONFIG->{peer}->{$_}->{listen}?$Inject::CONFIG->{peer}->{$_}->{listen}:1),
			Passive => ($Inject::CONFIG->{peer}->{$_}->{passive}?$Inject::CONFIG->{peer}->{$_}->{passive}:0),
			ConnectRetryTime 	=> ($Inject::CONFIG->{peer}->{$_}->{connectretrytime}?$Inject::CONFIG->{peer}->{$_}->{connectretrytime}:120),
			HoldTime 		=> ($Inject::CONFIG->{peer}->{$_}->{holdtime}?$Inject::CONFIG->{peer}->{$_}->{holdtime}:90),
			KeepAliveTime		=> ($Inject::CONFIG->{peer}->{$_}->{keepalivetime}?$Inject::CONFIG->{peer}->{$_}->{keepalivetime}:30),
			ErrorCallback           => \&peer_error,
			KeepaliveCallback       => \&peer_keepalive,
			NotificationCallback    => \&peer_notify,
			OpenCallback            => \&peer_open,
			UpdateCallback          => \&peer_update,
			RefreshCallback         => \&peer_refresh,
			ResetCallback           => \&peer_reset
		);

		# Start peer
		$PEERS->{$_}->{PeerID} = $_;

		if($Inject::CONFIG->{peer}->{$_}->{activate} ne "0") {
			$PEERS->{$_}->start();
		}

		$PEERS->{$_}->add_timer(\&process_peer, 1);
		$bgp->add_peer($PEERS->{$_});

		# Set peer information
		set_peer_info($_);
	}

	# Enter event loop
	$bgp->event_loop();
}


# Open callback
sub peer_open {
	my $peer = shift;

        # Lock $PEER_INFO
        lock($PEER_INFO);

	# Update flap statistics
	$PEER_INFO->{$peer->{PeerID}}->{_open_count}++;

	if($DEBUG->{open}) {
		print "\n", get_time(), "BGP-5-ADJCHANGE: Neighbor ",
		      $peer->{PeerID}, " (", $peer->{_peer_id}, " / ", 
	 	      $peer->{_peer_as}, ") is up.\n\n";
	}
}


# Reset callback
sub peer_reset {
	my $peer = shift;

	# Update statistics
	{
        	# Lock $PEER_INFO
        	lock($PEER_INFO);

		# Update flap statistics
		$PEER_INFO->{$peer->{PeerID}}->{_reset_count}++;
	};

	{
		# Lock $ROUTES_IN
		lock($ROUTES_IN);
		no warnings;
		$ROUTES_IN->{_recvd_prefixes} -= $ROUTES_IN->{$peer->{PeerID}}->{_recvd_prefixes};
		delete $ROUTES_IN->{$peer->{PeerID}};
	};

	{
		# Lock $ROUTES_OUT
		lock($ROUTES_OUT);
	
		# Unmark routes (so they will be reinjected when the peer comes up)
		foreach (keys %{$ROUTES_OUT}) {
			if($ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_injected} == 1) {
				$ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_withdraw} = 0;
				$ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_inject}   = 1;
				$ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_injected} = 0;
			}
		}
	};

	if($DEBUG->{reset}) {
		print "\n", get_time(), "BGP-RESET: Neighbor ",
		      $peer->{PeerID}, " (", $peer->{_peer_id}, " / ", 
	 	      $peer->{_peer_as}, ") reset.\n\n";
	}
}


# Keepalive callback
sub peer_keepalive {
	my $peer = shift;

	if($DEBUG->{keepalives}) {
		print "\n", get_time(), "BGP-KEEPALIVE: Received ",
		      "keepalive from ", $peer->{PeerID}, " (",
		      $peer->{_peer_id}, " / ",  $peer->{_peer_as}, ")\n\n";
	}
}


# Refresh callback
sub peer_refresh {
	my ($peer, $refresh) = (shift, shift);

	if($DEBUG->{refresh}) {
		print "\n", get_time(), "BGP-REFRESH: Neighbor ",
		      $peer->{PeerID}, " (", $peer->{_peer_id}, " / ", 
	 	      $peer->{_peer_as}, ") refresh.\n";

		if($refresh) {
			print "\nAFI and SAFI information of refresh packet:\n\n";
			print "AFI : ", $refresh->afi(), "\n";
			print "SAFI: ", $refresh->safi(), "\n";
		}
	}

	print "\n";
}


# Notification callback
sub peer_notify {
	my ($peer, $error) = (shift, shift);

	if($DEBUG->{notify}) {
		print "\n", get_time(), "BGP-NOTIFICATION: Neighbor ",
		      $peer->{PeerID}, " (", $peer->{_peer_id}, " / ", 
	 	      $peer->{_peer_as}, ") notification:\n";

		if($error) {
			no warnings;
			print "\nError       : ", $error->error_code(),
		              " (".$BGP_ERROR_CODE[$error->error_code()].")\n";
			print "ErrorSubCode: ", $error->error_subcode(), 
			      " (", ret_bgp_sub_error(
					$error->error_code(), 
					$error->error_subcode()
			      ), ")\n";

			if($error->error_data() !~ /^\s*$/) {
				print "ErrorData   : ", conv($error->error_data()), "\n";
			}
		}

		print "\n";
	}
}


# Update callback
sub peer_update {
	my ($peer, $update) = (shift, shift);

        # Lock $ROUTES_IN
        lock($ROUTES_IN);

	# Get NLRI, WITHDRAWN routes and prefixes
	my $nlri = $update->nlri();
	my $withdrawn = $update->withdrawn();
	my $nlri_cnt = scalar(@{$nlri});
	my $withdrawn_cnt = scalar(@{$withdrawn});
	my $prefix = $update->ashash();

	# Save statistics
	{
		no warnings;
		$ROUTES_IN->{_recvd_updates}++;
		$ROUTES_IN->{_recvd_nlri} += $nlri_cnt;
		$ROUTES_IN->{_recvd_withdrawn} += $withdrawn_cnt;
		$ROUTES_IN->{_recvd_prefixes} += $nlri_cnt;
		$ROUTES_IN->{_recvd_prefixes} -= $withdrawn_cnt;

		if(!$ROUTES_IN->{$peer->{PeerID}}) {
			$ROUTES_IN->{$peer->{PeerID}} = &share({});
		}

		$ROUTES_IN->{$peer->{PeerID}}->{_recvd_updates}++;
		$ROUTES_IN->{$peer->{PeerID}}->{_recvd_nlri} += $nlri_cnt;
		$ROUTES_IN->{$peer->{PeerID}}->{_recvd_withdrawn} += $withdrawn_cnt;
		$ROUTES_IN->{$peer->{PeerID}}->{_recvd_prefixes} += $nlri_cnt;
		$ROUTES_IN->{$peer->{PeerID}}->{_recvd_prefixes} -= $withdrawn_cnt;
	};

	# Update routes
	foreach(@{$nlri}) {
		if(!$ROUTES_IN->{$peer->{PeerID}}->{$_}) {
			$ROUTES_IN->{$peer->{PeerID}}->{$_} = &share({});
		}

		$ROUTES_IN->{$peer->{PeerID}}->{$_}->{_next_hop} = $prefix->{$_}->{_next_hop};
		$ROUTES_IN->{$peer->{PeerID}}->{$_}->{_origin} = $prefix->{$_}->{_origin};
		$ROUTES_IN->{$peer->{PeerID}}->{$_}->{_med} = $prefix->{$_}->{_med};
		$ROUTES_IN->{$peer->{PeerID}}->{$_}->{_aggregator} = shared_clone($prefix->{$_}->{_aggregator});

		$ROUTES_IN->{$peer->{PeerID}}->{$_}->{_as_path} = shared_clone($prefix->{$_}->{_as_path}->asarray);
		$ROUTES_IN->{$peer->{PeerID}}->{$_}->{_communities} = shared_clone($prefix->{$_}->{_communities});
		$ROUTES_IN->{$peer->{PeerID}}->{$_}->{_atomic_agg} = $prefix->{$_}->{_atomic_agg},
		$ROUTES_IN->{$peer->{PeerID}}->{$_}->{_local_pref} = $prefix->{$_}->{_local_pref},
		$ROUTES_IN->{$peer->{PeerID}}->{$_}->{_attr_mask} = shared_clone($prefix->{$_}->{_attr_mask});
	};

	# Remove withdrawn routes
	foreach(@{$withdrawn}) {
		delete $ROUTES_IN->{$peer->{PeerID}}->{$_};
	}

	if($DEBUG->{update}) {
		print "\n", get_time(), "BGP-UPDATE: Neighbor ",
		      $peer->{PeerID}, " (", $peer->{_peer_id}, " / ", 
	 	      $peer->{_peer_as}, ") update:\n";

		if($withdrawn_cnt > 0) {
			print "\nWithdrawn:\n";
			foreach (@{$withdrawn}) {
				print "  -> $_\n";

				# Detailed debugging
				if($DEBUG->{update} == 2) {
					show_prefix_detail($prefix->{$_});
				}
			}
		}

		if($nlri_cnt > 0) {
			print "\nNLRI:\n";
			foreach (@{$nlri}) {
				print "  -> $_\n";

				# Detailed debugging
				if($DEBUG->{update} == 2) {
					show_prefix_detail($prefix->{$_});
				}
			}
		}

		print "\n";
	}

}


# Error callback
sub peer_error {
	my ($peer, $error) = (shift, shift);

	if($DEBUG->{error}) {
		print "\n", get_time(), "BGP-ERROR: Neighbor ",
		      $peer->{PeerID}, " (", $peer->{_peer_id}, " / ", 
	 	      $peer->{_peer_as}, ") error:\n";

		if($error) {
			no warnings;
			print "\nThe following error codes were logged:\n\n";
			print "Error       : ", $error->error_code(),
			      " (".$BGP_ERROR_CODE[$error->error_code()].")\n";
			print "ErrorSubCode: ", $error->error_subcode(),
			      " (", ret_bgp_sub_error(
					$error->error_code(), 
					$error->error_subcode()
		       	      ), ")\n";

			if($error->error_data() !~ /^\s*$/) {
				print "ErrorData   : ", conv($error->error_data()), "\n";
			}
		}

		print "\n";
	}
}


# Process peer
sub process_peer {
	my $peer = shift;

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

        # Lock $PEER_INFO
        lock($PEER_INFO);

	# Check if exit was requested
	if($PEER_INFO->{_exit_requested}) {
		$peer->stop();
		threads->exit();
	}

	# Check peer flaps
	if($PEER_INFO->{$peer->{PeerID}}->{_flap} == 1) {
		if($PEER_INFO->{$peer->{PeerID}}->{_flap_state} == 0) {
			next;
		# Check if it is the first time we should flap
		} elsif($PEER_INFO->{$peer->{PeerID}}->{_flap_state} == 1) {
			# Check if peer is established
			if($peer->is_established()) {
				$PEER_INFO->{$peer->{PeerID}}->{_up_s_current} = $PEER_INFO->{$peer->{PeerID}}->{_up_s} - 1;
				$PEER_INFO->{$peer->{PeerID}}->{_flap_state} = 2;
			} else {
				$PEER_INFO->{$peer->{PeerID}}->{_down_s_current} = $PEER_INFO->{$peer->{PeerID}}->{_down_s} - 1;
				$PEER_INFO->{$peer->{PeerID}}->{_flap_state} = 3;
			}
		} else {
			# Check if flap time is over
			if($PEER_INFO->{$peer->{PeerID}}->{_up_s_current} == 0 &&
			   $PEER_INFO->{$peer->{PeerID}}->{_flap_state} == 2
			) {
				if($Inject::CONFIG->{debug}->{flap} == 1) {
					print "\n", get_time(), "INFO: Flap time for peer ", $peer->{PeerID}, " is over -> Stopping...\n";
				}

				$peer->stop();
				$PEER_INFO->{$peer->{PeerID}}->{_up_s_current} = $PEER_INFO->{$peer->{PeerID}}->{_up_s};
				$PEER_INFO->{$peer->{PeerID}}->{_flap_state} = 3;
			} elsif($PEER_INFO->{$peer->{PeerID}}->{_down_s_current} == 0 &&
			        $PEER_INFO->{$peer->{PeerID}}->{_flap_state} == 3
			) {
				if($Inject::CONFIG->{debug}->{flap} == 1) {
					print "\n", get_time(), "INFO: Flap time for peer ", $peer->{PeerID}, " is over -> Starting...\n";
				}

				$peer->start();
				$PEER_INFO->{$peer->{PeerID}}->{_down_s_current} = $PEER_INFO->{$peer->{PeerID}}->{_down_s};
				$PEER_INFO->{$peer->{PeerID}}->{_flap_state} = 2;
			} elsif($PEER_INFO->{$peer->{PeerID}}->{_up_s_current} > 0 &&
				$PEER_INFO->{$peer->{PeerID}}->{_flap_state} == 2
			) {
				$PEER_INFO->{$peer->{PeerID}}->{_up_s_current}--;
			} elsif($PEER_INFO->{$peer->{PeerID}}->{_down_s_current} > 0 &&
				$PEER_INFO->{$peer->{PeerID}}->{_flap_state} == 3
			) {
				$PEER_INFO->{$peer->{PeerID}}->{_down_s_current}--;
			} else {
				if($Inject::CONFIG->{debug}->{flap} == 1) {
					print "\n", get_time(), "ERROR: Invalid peer flap state:\n\n";
				}
			}
		}
	}


	# Check route flaps
	no warnings;
	foreach(keys %{$ROUTES_OUT}) {
		foreach my $rp (keys %{$PEER_INFO}) {
			if($ROUTES_OUT->{$_}->{$rp}->{_flap} == 1) {
				# Check if peer is in established state
				next if $peer->{PeerID} ne $rp;
				if(!$peer->is_established()) {
					if($Inject::CONFIG->{debug}->{flap} == 1) {
						print "\n", get_time(), "ERROR: Peer $rp is down, ignoring flap for RID $_\n\n";
					}
					next;
				}

				if($ROUTES_OUT->{$_}->{$rp}->{_flap_state} == 0) {
					next;
				# Check if it is the first time we should flap
				} elsif($ROUTES_OUT->{$_}->{$rp}->{_flap_state} == 1) {
					# Check if route is injected
					if($ROUTES_OUT->{$_}->{$rp}->{_injected}) {
						$ROUTES_OUT->{$_}->{$rp}->{_up_s_current} = $ROUTES_OUT->{$_}->{$rp}->{_up_s} - 1;
						$ROUTES_OUT->{$_}->{$rp}->{_flap_state} = 2;
					} else {
						$ROUTES_OUT->{$_}->{$rp}->{_down_s_current} = $ROUTES_OUT->{$_}->{$rp}->{_down_s} - 1;
						$ROUTES_OUT->{$_}->{$rp}->{_flap_state} = 3;
					}
				} else {
					# Check if flap time is over
					if($ROUTES_OUT->{$_}->{$rp}->{_up_s_current} == 0 &&
			   		   $ROUTES_OUT->{$_}->{$rp}->{_flap_state} == 2
					) {
						if($Inject::CONFIG->{debug}->{flap} == 1) {
							print "\n", get_time(), "INFO: Flap time for route ", $_, " is over -> Withdrawing...\n";
						}

						$ROUTES_OUT->{$_}->{$rp}->{_withdraw} = 1;
						$ROUTES_OUT->{$_}->{$rp}->{_inject} = 0;
						$ROUTES_OUT->{$_}->{$rp}->{_injected} = 1;
						$ROUTES_OUT->{$_}->{$rp}->{_up_s_current} = $ROUTES_OUT->{$_}->{$rp}->{_up_s};
						$ROUTES_OUT->{$_}->{$rp}->{_flap_state} = 3;
					} elsif($ROUTES_OUT->{$_}->{$rp}->{_down_s_current} == 0 &&
			        		$ROUTES_OUT->{$_}->{$rp}->{_flap_state} == 3
					) {
						if($Inject::CONFIG->{debug}->{flap} == 1) {
							print "\n", get_time(), "INFO: Flap time for route ", $_, " is over -> Starting...\n";
						}

						$ROUTES_OUT->{$_}->{$rp}->{_withdraw} = 1;
						$ROUTES_OUT->{$_}->{$rp}->{_inject} = 1;
						$ROUTES_OUT->{$_}->{$rp}->{_injected} = 1;
						$ROUTES_OUT->{$_}->{$rp}->{_down_s_current} = $ROUTES_OUT->{$_}->{$rp}->{_down_s};
						$ROUTES_OUT->{$_}->{$rp}->{_flap_state} = 2;
					} elsif($ROUTES_OUT->{$_}->{$rp}->{_up_s_current} > 0 &&
						$ROUTES_OUT->{$_}->{$rp}->{_flap_state} == 2
					) {
						$ROUTES_OUT->{$_}->{$rp}->{_up_s_current}--;
					} elsif($ROUTES_OUT->{$_}->{$rp}->{_down_s_current} > 0 &&
						$ROUTES_OUT->{$_}->{$rp}->{_flap_state} == 3
					) {
						$ROUTES_OUT->{$_}->{$rp}->{_down_s_current}--;
					} else {
						if($Inject::CONFIG->{debug}->{flap} == 1) {
							print "\n", get_time(), "ERROR: Invalid peer flap state:\n\n";
						}
					}
				}
			}
		}
	}

	# Check if we should start / stop a peer
	{
		no warnings;
		if($PEER_INFO->{$peer->{PeerID}}->{_start} == 1) {
			if($peer->is_established()) {
				print "\n", get_time(), "ERROR: Peer ", $peer->{PeerID}, " is already started.\n\n";
				$PEER_INFO->{$peer->{PeerID}}->{_start} = 0;
			} else {
				print "\n", get_time(), "INFO: Starting peer ", $peer->{PeerID}, "\n\n";
				$peer->start();
				$PEER_INFO->{$peer->{PeerID}}->{_start} = 0;
			}
		} elsif($PEER_INFO->{$peer->{PeerID}}->{_stop} == 1) {
			if(!$peer->is_established()) {
                                print "\n", get_time(), "ERROR: Peer ", $peer->{PeerID}, " is already stopped.\n\n";
                                $PEER_INFO->{$peer->{PeerID}}->{_stop} = 0;
                        } else {
                                print "\n", get_time(), "INFO: Stopping peer ", $peer->{PeerID}, "\n\n";
                                $peer->stop();
                                $PEER_INFO->{$peer->{PeerID}}->{_stop} = 0;
                        }
		}
	};

	# Update peer information
	set_peer_info($peer->{PeerID});

        # Lock $ROUTES_IN
        lock($ROUTES_IN);

	if(!$ROUTES_IN->{$peer->{PeerID}}) {
		$ROUTES_IN->{$peer->{PeerID}} = &share({});
		$ROUTES_IN->{$peer->{PeerID}}->{_sent_prefixes} = 0;
		$ROUTES_IN->{$peer->{PeerID}}->{_recvd_prefixes} = 0;
	}

	# Update object
	my $update;

	# Check each route id
	foreach (keys %{$ROUTES_OUT}) {
		# Check if peer is in established state
		if(!$peer->is_established()) {
			next;
		}

		# Check what we have to do with the route
		# Route should be withdrawn and not reinjected
		if(
		  $ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_withdraw} == 1 &&
		  $ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_inject}   == 0 &&
		  $ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_injected} == 1
		) {
		  	print "\n", get_time(), "INFO: Withdrawing RID $_ on ", $peer->{PeerID}, "\n";

			# Construct update
			$update = Net::BGP::Update->new(
				Withdraw => [ $ROUTES_OUT->{$_}->{_route} ]
			);

			# Send update
			$peer->update($update);

		  	$ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_injected} = 0;
		  	$ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_withdraw} = 0;

			# Update statistics
			$ROUTES_IN->{_sent_prefixes}--;
			$ROUTES_IN->{$peer->{PeerID}}->{_sent_prefixes}--;
		# Route should be withdrawn and reinjected
		} elsif(
		  $ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_withdraw} == 1 &&
		  $ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_inject}   == 1 &&
		  $ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_injected} == 1
		) {
			if($DEBUG->{withdraw}) {
				print "\n", get_time(), "INFO: Withdrawing and reinjecting RID $_ on ", $peer->{PeerID}, ".\n\n";
			}

			# Construct update
			$update = Net::BGP::Update->new(
				Withdraw => [ $ROUTES_OUT->{$_}->{_route} ],
				NLRI => [ $ROUTES_OUT->{$_}->{_route} ],
				Origin => $ROUTES_OUT->{$_}->{_origin},
				NextHop => $ROUTES_OUT->{$_}->{_next_hop},
				LocalPref => $ROUTES_OUT->{$_}->{_local_pref},
				MED => $ROUTES_OUT->{$_}->{_med},
				AsPath => $ROUTES_OUT->{$_}->{_as_path},
				Communities => $ROUTES_OUT->{$_}->{_communities}?[ split(" ", $ROUTES_OUT->{$_}->{_communities}) ]:[],
				Aggregator => $ROUTES_OUT->{$_}->{_aggregator}->{_as}?[ $ROUTES_OUT->{$_}->{_aggregator}->{_as}, $ROUTES_OUT->{$_}->{_aggregator}->{_aggregator} ]:[],
				AtomicAggregate => $ROUTES_OUT->{$_}->{_atomic}==0?undef:1,
			);

			# Send update
			$peer->update($update);

			# Update routes
			$ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_injected} = 1;
			$ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_inject} = 0;
			$ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_withdraw} = 0;
		# Route should be injected
		} elsif(
		  $ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_withdraw} == 0 &&
		  $ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_inject} == 1 &&
		  $ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_injected} == 0
		) {
			if($DEBUG->{inject}) {
				print "\n", get_time(), "INFO: Injecting RID $_ on ", $peer->{PeerID}, "\n\n";
			}

			# Update statistics
			$ROUTES_IN->{_sent_prefixes}++;
			$ROUTES_IN->{$peer->{PeerID}}->{_sent_prefixes}++;

			# Construct update
			$update = Net::BGP::Update->new(
				NLRI => [ $ROUTES_OUT->{$_}->{_route} ],
				Origin => $ROUTES_OUT->{$_}->{_origin},
				NextHop => $ROUTES_OUT->{$_}->{_next_hop},
				LocalPref => $ROUTES_OUT->{$_}->{_local_pref},
				MED => $ROUTES_OUT->{$_}->{_med},
				AsPath => $ROUTES_OUT->{$_}->{_as_path},
				Communities => $ROUTES_OUT->{$_}->{_communities}?[ split(" ", $ROUTES_OUT->{$_}->{_communities}) ]:[],
				Aggregator => $ROUTES_OUT->{$_}->{_aggregator}->{_as}?[ $ROUTES_OUT->{$_}->{_aggregator}->{_as}, $ROUTES_OUT->{$_}->{_aggregator}->{_aggregator} ]:[],
				AtomicAggregate => $ROUTES_OUT->{$_}->{_atomic}==0?undef:1,
				MED => $ROUTES_OUT->{$_}->{_med}
			);

			# Send update
			$peer->update($update);

			# Update routes
			$ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_injected} = 1;
			$ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_inject} = 0;
		# Route should be injected, but is already
		# injected -> Looks like a bug :)
		} elsif(
		   $ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_withdraw} == 0 &&
		   $ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_inject} == 1 &&
		   $ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_injected} == 1
		) {
			if($DEBUG->{inject}) {
				print "\n", get_time(), "ERROR: Route should be injected, but is already injected.\n\n";
			}
		# Route should be withdrawn, but is not injected
		# -> Looks like a bug
		} elsif(
		  $ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_withdraw} == 1 &&
		  $ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_injected} == 0
		) {
			if($DEBUG->{withdraw}) {
				print "\n", get_time(), "ERROR: Route should be withdrawn, but is not injected.\n\n";
			}
		}


		# Remove route
		if($ROUTES_OUT->{$_}->{$peer->{PeerID}}->{_remove} == 1) {
			delete $ROUTES_OUT->{$_};
		}
	}

}


# Set peer information
sub set_peer_info {
	my $PEER_ID = shift;

        # Lock $PEER_INFO
        lock($PEER_INFO);

	# Peer information
	if(!$PEER_INFO->{$PEER_ID}) {
		$PEER_INFO->{$PEER_ID} = &share({});
		$PEER_INFO->{$PEER_ID}->{_flap} = 0;
	}

	$PEER_INFO->{$PEER_ID}->{_passive} = $PEERS->{$PEER_ID}->{_passive};
	$PEER_INFO->{$PEER_ID}->{_peer_as} = $PEERS->{$PEER_ID}->{_peer_as};
	$PEER_INFO->{$PEER_ID}->{_bgp_version} = $PEERS->{$PEER_ID}->{_bgp_version};
	$PEER_INFO->{$PEER_ID}->{_refresh} = $PEERS->{$PEER_ID}->{_refresh};
	$PEER_INFO->{$PEER_ID}->{_listen} = $PEERS->{$PEER_ID}->{_listen};
	$PEER_INFO->{$PEER_ID}->{_local_as} = $PEERS->{$PEER_ID}->{_local_as};
	$PEER_INFO->{$PEER_ID}->{_peer_port} = $PEERS->{$PEER_ID}->{_peer_port};
	$PEER_INFO->{$PEER_ID}->{_peer_id} = $PEERS->{$PEER_ID}->{_peer_id};
	$PEER_INFO->{$PEER_ID}->{_local_id} = $PEERS->{$PEER_ID}->{_local_id};

	# Transport information
	$PEER_INFO->{$PEER_ID}->{_out_msg_buffer} = $PEERS->{$PEER_ID}->{_transport}->{_out_msg_buffer};
	$PEER_INFO->{$PEER_ID}->{_peer_socket_connected} = $PEERS->{$PEER_ID}->{_transport}->{_peer_socket_connected};
	$PEER_INFO->{$PEER_ID}->{_fsm_state} = $Net::BGP::Transport::BGP_STATES[$PEERS->{$PEER_ID}->{_transport}->{_fsm_state}];
	$PEER_INFO->{$PEER_ID}->{_hold_timer} = $PEERS->{$PEER_ID}->{_transport}->{_hold_timer};
	$PEER_INFO->{$PEER_ID}->{_event_queue} = &share([]);
	$PEER_INFO->{$PEER_ID}->{_event_queue} = @{$PEERS->{$PEER_ID}->{_transport}->{_event_queue}};
	$PEER_INFO->{$PEER_ID}->{_peer_refresh} = $PEERS->{$PEER_ID}->{_transport}->{_peer_refresh};
	$PEER_INFO->{$PEER_ID}->{_connect_retry_time} = $PEERS->{$PEER_ID}->{_transport}->{_connect_retry_time};
	$PEER_INFO->{$PEER_ID}->{_hold_time} = $PEERS->{$PEER_ID}->{_transport}->{_hold_time};
	$PEER_INFO->{$PEER_ID}->{_in_msg_buf_type} = $PEERS->{$PEER_ID}->{_transport}->{_in_msg_buf_type};
	$PEER_INFO->{$PEER_ID}->{_keep_alive_timer} = $PEERS->{$PEER_ID}->{_transport}->{_keep_alive_timer};
	$PEER_INFO->{$PEER_ID}->{_in_msg_buf_bytes_exp} = $PEERS->{$PEER_ID}->{_transport}->{_in_msg_buf_bytes_exp};
	$PEER_INFO->{$PEER_ID}->{_in_msg_buf_state} = $PEERS->{$PEER_ID}->{_transport}->{_in_msg_buf_state};
	$PEER_INFO->{$PEER_ID}->{_bgp_version} = $PEERS->{$PEER_ID}->{_transport}->{_bgp_version};
	$PEER_INFO->{$PEER_ID}->{_keep_alive_time} = $PEERS->{$PEER_ID}->{_transport}->{_keep_alive_time};
	$PEER_INFO->{$PEER_ID}->{_connect_retry_timer} = $PEERS->{$PEER_ID}->{_transport}->{_connect_retry_timer};
	$PEER_INFO->{$PEER_ID}->{_last_timer_update} = $PEERS->{$PEER_ID}->{_transport}->{_last_timer_update};
	$PEER_INFO->{$PEER_ID}->{_peer_announced_id} = $PEERS->{$PEER_ID}->{_transport}->{_peer_announced_id};
	$PEER_INFO->{$PEER_ID}->{_in_msg_buffer} = $PEERS->{$PEER_ID}->{_transport}->{_in_msg_buffer};
	$PEER_INFO->{$PEER_ID}->{_message_queue} = &share([]);
	$PEER_INFO->{$PEER_ID}->{_message_queue} = @{$PEERS->{$PEER_ID}->{_transport}->{_message_queue}};
}


# Return BGP suberror message
sub ret_bgp_sub_error {
	my($error, $suberror) = @_;

	if($error == 1) {
		return($BGP_SUB_ERROR_CODE_MSG[$suberror]);
	} elsif($error == 2) {
		return($BGP_SUB_ERROR_CODE_OPEN[$suberror]);
	} elsif($error == 3) {
		return($BGP_SUB_ERROR_CODE_UPDATE[$suberror]);
	} elsif($error == 6) {
		return($BGP_SUB_ERROR_CODE_CEASE[$suberror]);
	} else {
		return("Invalid error / suberror combination");
	}
}


# Show prefix details
sub show_prefix_detail {
	my $prefix = shift;

	no warnings;
	print "\tNext Hop   : ", $prefix->{_next_hop}, "\n";
	print "\tOrigin     : ", $prefix->{_origin}, " (", 
		map_origin($prefix->{_origin}), 
	      ")\n";
	print "\tLocalpref  : ",
	      $prefix->{_local_pref}?$prefix->{_local_pref}:"None (EBGP)", 
	      "\n";
	print "\tMED        : ", $prefix->{_med}?$prefix->{_med}:"None", "\n";

	if(scalar(@{$prefix->{_aggregator}}) > 0) {
		print "\tAggregator : ", map($_." ", @{$prefix->{_aggregator}}), "\n";
	}

	if($prefix->{_atomic_agg}) {
		print "\tAtomic aggr: ", $prefix->{_atomic_agg}, "\n";
	}

	print "\tAS Path    : ", $prefix->{_as_path}, "\n";
	print "\tCommunities: ", map($_." ", @{$prefix->{_communities}}), "\n";
	print "\tAttr mask  : ", map($_." ", @{$prefix->{_attr_mask}}), "\n";

	print "\n";
}


1;
__END__

