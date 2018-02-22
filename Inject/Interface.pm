# Set package
package Inject::Interface;

# Version
$VERSION = $Inject::VERSION;

# Modules
use warnings;
use strict;
use base 'Inject';
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use Inject::BGP;
use Inject::Utils;
use Inject::Term;
use Data::Dumper;
use threads;
use threads::shared;
use Network::IPv4Addr qw(ipv4_network);

require Exporter;

@ISA = qw(Exporter AutoLoader);

@EXPORT = qw(
);

our %EXPORT_TAGS = (
	'all' => [ qw(
		 ) ]
);


# Make aliases for variables
our $DEBUG = ();
*DEBUG = *Inject::DEBUG;

our $PEER_INFO = ();
*PEER_INFO = *Inject::PEER_INFO;

our $ROUTES_IN = ();
*ROUTES_IN = *Inject::ROUTES_IN;

our $ROUTES_OUT = ();
*ROUTES_OUT = *Inject::ROUTES_OUT;

our $TEST_DATA = ();
*TEST_DATA = *Inject::TEST_DATA;

my $term;

# Function cmdline_t
sub cmdline_t {
	# Initialize terminal
	$term = term(); 

	print "\nInject v$Inject::VERSION - (c) by Martin Kluge <mk\@elxsi.de>\n";
	print "="x48, "\n\n";
	print "Type \"help\", \"h\" or \"?\" for command overview.\n\n";

	# Run term
	$term->load_history();

	while(!$term->{done}) {
		$term->process_a_cmd();
	}

	$term->save_history();
}


# Function _cmd_exit
sub _cmd_exit {
	print get_time(), "INFO: Exiting program.\n\n";


	# Request exit
	$term->exit_requested(1);

	# Stop all peers
	{
		# Lock $PEER_INFO
		lock($PEER_INFO);
		foreach(keys %{$PEER_INFO}) {
			$PEER_INFO->{$_}->{_stop} = 1;
		}
	}

	# Wait 2 seconds
	sleep(4);
	$PEER_INFO->{_exit_requested} = 1;
}


# Function _cmd_show_config
sub _cmd_show_config {
	print get_time(), "INFO: Configuration: $Inject::CFG_FILE\n\n";
	$Data::Dumper::Terse  = 1;
	$Data::Dumper::Indent = 1;
	$Data::Dumper::Purity = 1;

	print Dumper($Inject::CONFIG);
	print "\n";
}


# Function _cmd_show_debug
sub _cmd_show_debug {
	my $arg = shift;

	# Lock $DEBUG
	lock($DEBUG);

	if(!$arg) {
		print get_time(), "INFO: Active debugging options:\n\n";
		$Data::Dumper::Terse  = 1;
		$Data::Dumper::Indent = 1;
		$Data::Dumper::Purity = 1;
	
		print $DEBUG ? Dumper($DEBUG) : "None";
		print "\n";
	} else {
		print get_time(), "INFO Debugging for $arg is ".
		      ($DEBUG->{$arg}?"enabled":"disabled").
		      ".\n\n";
	}
}


# Function _cmd_debug_all
sub _cmd_debug_all {
	my $arg = shift;

	# Lock $DEBUG
	lock($DEBUG);

	if(!$arg) {
		$DEBUG->{flap} 		= 1;
		$DEBUG->{withdraw} 	= 1;
		$DEBUG->{open} 		= 1;
		$DEBUG->{reset} 	= 1;
		$DEBUG->{keepalives} 	= 1;
		$DEBUG->{refresh} 	= 1;
		$DEBUG->{notify} 	= 1;
		$DEBUG->{update} 	= 2;
		$DEBUG->{error} 	= 1;
		print get_time(), "INFO: Debugging of all features enabled.\n";
	} elsif($arg =~ /^off$/) {
		$DEBUG->{flap} 		= 0;
		$DEBUG->{withdraw} 	= 0;
		$DEBUG->{open} 		= 0;
		$DEBUG->{reset} 	= 0;
		$DEBUG->{keepalives} 	= 0;
		$DEBUG->{refresh} 	= 0;
		$DEBUG->{notify} 	= 0;
		$DEBUG->{update} 	= 0;
		$DEBUG->{error} 	= 0;
		print get_time(), "INFO: Debugging of all features disabled.\n";
	} else {
		print get_time(), "ERROR: Invalid command args.\n";
	}

	print "\n";
}


# Function _cmd_debug_inject
sub _cmd_debug_inject {
	set_debug("inject", shift, "route injections");
}


# Function _cmd_debug_withdraw
sub _cmd_debug_withdraw {
	set_debug("withdraw", shift, "route withdraws");
}


# Function _cmd_debug_flap
sub _cmd_debug_flap {
	set_debug("flap", shift, "session and route flaps");
}


# Function _cmd_debug_open
sub _cmd_debug_open {
	set_debug("open", shift, "session openings");
}


# Function _cmd_debug_reset
sub _cmd_debug_reset {
	set_debug("reset", shift, "session resets");
}
	

# Function _cmd_debug_keepalives
sub _cmd_debug_keepalives {
	set_debug("keepalives", shift, "keepalive packets");
}


# Function _cmd_debug_refresh
sub _cmd_debug_refresh {
	set_debug("refresh", shift, "refresh packets");
}


# Function _cmd_debug_notify
sub _cmd_debug_notify {
	set_debug("notify", shift, "notification packets");
}


# Function _cmd_debug_update
sub _cmd_debug_update {
	set_debug("update", shift, "update packets");
}


# Function _cmd_debug_error
sub _cmd_debug_error {
	set_debug("error", shift, "errors");
}


# Function _cmd_flap_peer
sub _cmd_flap_peer {
	my($peer, $up_s, $down_s) = (shift, shift, shift);

	# Lock $PEER_INFO
	lock($PEER_INFO);

	foreach(keys %{$PEER_INFO}) {
		if(lc($peer) eq "all" || $peer eq $_) {
			$PEER_INFO->{$_}->{_flap} = 1;
			$PEER_INFO->{$_}->{_flap_state} = 1;
			$PEER_INFO->{$_}->{_up_s} = $up_s;
			$PEER_INFO->{$_}->{_down_s} = $down_s;
			$PEER_INFO->{$_}->{_up_s_current} = $up_s;
			$PEER_INFO->{$_}->{_down_s_current} = $down_s;
			print get_time(), "INFO: Flapping for peer $_ enabled (UP=$up_s / DOWN=$down_s)\n\n";
		}
	}
}


# Function _cmd_unflap_peer
sub _cmd_unflap_peer {
	my $peer = shift;

	# Lock $PEER_INFO
	lock($PEER_INFO);

	foreach(keys %{$PEER_INFO}) {
		if(lc($peer) eq "all" || $peer eq $_) {
			$PEER_INFO->{$_}->{_flap} = 0;
			$PEER_INFO->{$_}->{_flap_state} = 0;
			$PEER_INFO->{$_}->{_up_s} = 0;
			$PEER_INFO->{$_}->{_down_s} = 0;
			$PEER_INFO->{$_}->{_up_s_current} = 0;
			$PEER_INFO->{$_}->{_down_s_current} = 0;
			print get_time(), "INFO: Flapping for peer $_ disabled\n\n";
		}
	}
}


# Function _cmd_flap_route
sub _cmd_flap_route {
	my($peer, $rid, $up_s, $down_s) = (shift, shift, shift, shift);

        # Lock $PEER_INFO
        lock($PEER_INFO);

	# Lock $ROUTES_OUT
	lock($ROUTES_OUT);

	foreach(keys %{$PEER_INFO}) {
		if(lc($peer) eq "all" || $peer eq $_) {
			foreach my $route (keys %{$ROUTES_OUT}) {
				$ROUTES_OUT->{$route}->{$_}->{_flap} = 1;
				$ROUTES_OUT->{$route}->{$_}->{_flap_state} = 1;
				$ROUTES_OUT->{$route}->{$_}->{_up_s} = $up_s;
				$ROUTES_OUT->{$route}->{$_}->{_down_s} = $down_s;
				$ROUTES_OUT->{$route}->{$_}->{_up_s_current} = $up_s;
				$ROUTES_OUT->{$route}->{$_}->{_down_s_current} = $down_s;
				print get_time(), "INFO: Flapping for RID $route on peer $_ enabled (UP=$up_s / DOWN=$down_s)\n\n";
			}
		}
	}
}


# Function _cmd_unflap_route
sub _cmd_unflap_route {
	my($peer, $rid) = (shift, shift);

        # Lock $PEER_INFO
        lock($PEER_INFO);

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

	foreach(keys %{$PEER_INFO}) {
		if(lc($peer) eq "all" || $peer eq $_) {
			foreach my $route (keys %{$ROUTES_OUT}) {
				$ROUTES_OUT->{$route}->{$_}->{_flap} = 0;
				$ROUTES_OUT->{$route}->{$_}->{_flap_state} = 0;
				$ROUTES_OUT->{$route}->{$_}->{_up_s} = 0;
				$ROUTES_OUT->{$route}->{$_}->{_down_s} = 0;
				$ROUTES_OUT->{$route}->{$_}->{_up_s_current} = 0;
				$ROUTES_OUT->{$route}->{$_}->{_down_s_current} = 0;
				print get_time(), "INFO: Flapping for RID $route on peer $_ disabled.\n\n";
			}
		}
	}
}


# Function _cmd_inject
sub _cmd_inject {
	my($peer, $RID) = (shift, shift);

	# Disable warnings
	no warnings;

        # Lock $PEER_INFO
        lock($PEER_INFO);

	# Check peer
	$peer = lc($peer) if(lc($peer) eq "all");
	if(!$PEER_INFO->{$peer} && $peer ne "all") {
		print get_timer(), "ERROR: Invalid peer $peer\n\n";
		return;
	}

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

	# Check if route with RID has all mandatory parameters set
	if($ROUTES_OUT->{$RID}) {
		if(!$ROUTES_OUT->{$RID}->{_route}) {
			print get_time(), "ERROR: Mandatory parameter (network) is missing.\n\n";
			return;
		} elsif(!defined $ROUTES_OUT->{$RID}->{_origin}) {
			print get_time(), "ERROR: Mandatory parameter (origin) is missing.\n\n";
			return;
		} elsif(!$ROUTES_OUT->{$RID}->{_next_hop}) {
			print get_time(), "ERROR: Mandatory parameter (nexthop) is missing.\n\n";
			return;
		} else {

			# All mandatory options are set	- proceed
			print "\n";
			print get_time(), "INFO: Injecting the following route:\n\n";

			show_rid($RID, $peer);

			# Check if route was already injected
			if($peer eq "all") {
				foreach(keys %{$PEER_INFO}) {
					set_peer_iw($_, $RID);
				}
			} else {
				set_peer_iw($peer, $RID);
			}
		}
	} else {
		print get_time(), "ERROR: Route with RID $RID does not exist.\n\n";
	}
}


# Function _cmd_generate_routes
sub _cmd_generate_routes {
	my($peer, $cnt, @attr) = @_;

	# Random values
	my $RAND = ();

	# Disable warnings
	no warnings;

	# Flap counter
	my $flap_nr = 0;

	if($cnt == 0) {
		print "\n", get_time(), "ERROR: Invalid number of routes.\n\n";
		return;
	}


	# No error checks on the different attributes,
	# so user can inject invalid values
	foreach my $a (@attr) {
		if(lc($a) =~ /^flap\(/) {
			$RAND->{_flap} = strip_cmd($a);
			if($RAND->{_flap} < 0 || $RAND->{_flap} > 100) {
				print "\n", get_time(), "ERROR: Invalid value for attribute $a.\n\n";
				return;
			} else {
				$flap_nr = int(($RAND->{_flap} / $cnt)*100);
			}
		} elsif(lc($a) =~ /^nexthop\(/) {
			$RAND->{_next_hop} = strip_cmd($a);
		} elsif(lc($a) =~ /^origin\(/) {
			$RAND->{_origin} = strip_cmd($a);
		} elsif(lc($a) =~ /^localpref\(/) {
			$RAND->{_local_pref} = strip_cmd($a);
		} elsif(lc($a) =~ /^med\(/) {
			$RAND->{_med} = strip_cmd($a);
		} elsif(lc($a) =~ /^atomic\(/) {
			$RAND->{_atomic} = strip_cmd($a);
		} elsif(lc($a) =~ /^aggregator\(/) {
			$RAND->{_aggregator} = strip_cmd($a);
		} elsif(lc($a) =~ /^aspath\(/) {
			$RAND->{_as_path} = strip_cmd($a);
		} elsif(lc($a) =~ /^community\(/) {
			$RAND->{_communities} = strip_cmd($a);
		} else {
			print "\n", get_time(), "ERROR: Invalid attribute $_.\n\n";
			return;
		}
	}

	print "\n", get_time(), "INFO: Generating $cnt routes. One dot for each 1000 routes.\n\n";

	# Set autoflush
	$|=1;

	for(my $i=0; $i<$cnt; $i++) {
		{
			# Lock $ROUTES_OUT
			lock($ROUTES_OUT);

			if($i % 1000 == 0) {
				print ".";
			}

			# Delete RID
			$ROUTES_OUT->{"__$i"} = ();
			check_rid("__$i");

			# Set a random prefix
			$ROUTES_OUT->{"__$i"}->{_route} = (generate_prefix()).
							  "/".
							  (generate_netmask());

			# Set nexthop
			if(!defined $RAND->{_next_hop}) {
				$ROUTES_OUT->{"__$i"}->{_next_hop} = generate_prefix();
			} else {
				$ROUTES_OUT->{"__$i"}->{_next_hop} = ret_rand($RAND->{_next_hop});
			}

			# Set origin
			if(!defined $RAND->{_origin}) {
				$ROUTES_OUT->{"__$i"}->{_origin} = int(rand(3));
			} else {
				$ROUTES_OUT->{"__$i"}->{_origin} = ret_rand($RAND->{_origin});
			}
	
			# Set localpref
			if(!defined $RAND->{_local_pref}) {
				if(int(rand($Inject::CONFIG->{prop}->{local_pref})) == 0) {
					$ROUTES_OUT->{"__$i"}->{_local_pref} = int(rand(1025));
				}
			} else {
				$ROUTES_OUT->{"__$i"}->{_local_pref} = ret_rand($RAND->{_local_pref});
			}
	
			# Set MED
			if(!defined $RAND->{_med}) {
				if(int(rand($Inject::CONFIG->{prop}->{med})) == 0) {
					$ROUTES_OUT->{"__$i"}->{_med} = int(rand(1025));
				}
			} else {
				$ROUTES_OUT->{"__$i"}->{_med} = ret_rand($RAND->{_med});
			}
	
			# Set atomic aggregate
			if(!defined $RAND->{_atomic}) {
				if(int(rand($Inject::CONFIG->{prop}->{atomic})) == 0) {
					$ROUTES_OUT->{"__$i"}->{_atomic} = int(rand(2));
				}
			} else {
				$ROUTES_OUT->{"__$i"}->{_atomic} = ret_rand($RAND->{_atomic});
			}
	
			# Set aggregator
			if(!defined $RAND->{_aggregator}) {
				if(int(rand($Inject::CONFIG->{prop}->{aggregator})) == 0) {
					$ROUTES_OUT->{"__$i"}->{_aggregator}->{_aggregator} = generate_prefix();
					$ROUTES_OUT->{"__$i"}->{_aggregator}->{_as} = int(rand(65536));
				}
			} else {
				($ROUTES_OUT->{"__$i"}->{_aggregator}->{_as}, $ROUTES_OUT->{"__$i"}->{_aggregator}->{_aggregator}) = split(/:/, ret_rand($RAND->{_aggregator}));
			}
	
			# Set as path
			if(!defined $RAND->{_as_path}) {
				$ROUTES_OUT->{"__$i"}->{_as_path} = generate_as_path();
			} else {
				$ROUTES_OUT->{"__$i"}->{_as_path} = join(" ", split(/,/, ret_rand($RAND->{_as_path})));
			}
	
			# Set communities
			if(!defined $RAND->{_communities}) {
				if(int(rand($Inject::CONFIG->{prop}->{communities})) == 0) {
					$ROUTES_OUT->{"__$i"}->{_communities} = generate_communities();
				}
			} else {
				$ROUTES_OUT->{"__$i"}->{_communities} = join(" ", split(/,/, ret_rand($RAND->{_communities})));
			}
			
			# Check peers
			my $found = 0;
			{
				foreach (keys %{$PEER_INFO}) {
					if(lc($peer) eq "all" || $_ eq $peer) {
						$found = 1;

						# Set flaps
						if(defined $RAND->{_flap} &&
						   $i < $flap_nr
						) {
							$ROUTES_OUT->{"__$i"}->{$_}->{_flap} = 1;
							$ROUTES_OUT->{"__$i"}->{$_}->{_flap_state} = 1;
							$ROUTES_OUT->{"__$i"}->{$_}->{_up_s} = ret_flap_s();
							$ROUTES_OUT->{"__$i"}->{$_}->{_down_s} = ret_flap_s();
							$ROUTES_OUT->{"__$i"}->{$_}->{_up_s_current} = $ROUTES_OUT->{"__$i"}->{$_}->{_up_s};
							$ROUTES_OUT->{"__$i"}->{$_}->{_down_s_current} = $ROUTES_OUT->{"__$i"}->{$_}->{_down_s};
						}

						# Inject route
						$ROUTES_OUT->{"__$i"}->{$_}->{_inject} = 1;
					}
				}
			}

			if($found == 0) {
				print "\n", get_time(), "ERROR: Invalid peer $peer.\n";
				return;
			}
		};
	}
}


# Function _cmd_generate_remove
sub _cmd_generate_remove {
	# Lock $ROUTES_OUT
	lock($ROUTES_OUT);

	# Lock $PEER_INFO
	lock($PEER_INFO);

	print "\n", get_time(), "INFO: Removing all generated routes.\n\n";

	foreach my $route (keys %{$ROUTES_OUT}) {
		next if($route !~ /^__\d+$/);
		foreach (keys %{$PEER_INFO}) {
			$ROUTES_OUT->{$route}->{$_}->{_withdraw} = 1;
			$ROUTES_OUT->{$route}->{$_}->{_remove} = 1;
		}
	}
}


# Function _cmd_peer_start
sub _cmd_peer_start {
	my $peer = shift;

        # Lock $PEER_INFO
        lock($PEER_INFO);

	my $found = 0;

	foreach (keys %{$PEER_INFO}) {
		if(lc($peer) eq "all") {
			$found++;
			$PEER_INFO->{$_}->{_start} = 1;
		} elsif($_ eq $peer) {
			$found++;
			$PEER_INFO->{$_}->{_start} = 1;
		}
	}

	if($found == 0) {
		print get_time(), "ERROR: Peer $peer not found.\n\n";
	}
}


# Function _cmd_peer_stop
sub _cmd_peer_stop {
	my $peer = shift;

        # Lock $PEER_INFO
        lock($PEER_INFO);

	my $found = 0;

	foreach (keys %{$PEER_INFO}) {
		if(lc($peer) eq "all") {
			$found++;
			$PEER_INFO->{$_}->{_stop} = 1;
		} elsif($_ eq $peer) {
			$found++;
			$PEER_INFO->{$_}->{_stop} = 1;
		}
	}

	if($found == 0) {
		print get_time(), "ERROR: Peer $peer not found.\n\n";
	}
}


# Function _cmd_route_set_agg
sub _cmd_route_set_agg {
	my($RID, $as, $agg) = @_;

	# Check RID
	check_rid($RID);

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

	# Check if input is valid
	if(!is_16bit($as)) {
		print get_time(), "ERROR: $as is not a valid AS number.\n\n";
		return;
	} elsif(!is_ipv4($agg)) {
		print get_time(), "ERROR: $agg is not a valid aggregator IPv4 address.\n\n";
		return;
	}

	# Set aggregator
	$ROUTES_OUT->{$RID}->{_aggregator}->{_as} = $as;
	$ROUTES_OUT->{$RID}->{_aggregator}->{_aggregator} = $agg;

	print get_time(), "INFO: Route aggregator attribute for RID $RID set.\n\n";
}


# Function _cmd_route_set_atomic
sub _cmd_route_set_atomic {
	my($RID, $atomic) = @_;

	# Check RID
	check_rid($RID);

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

	if($atomic != 0 && $atomic != 1) {
		print get_time(), "ERROR: Atomic must be 0 (false) or 1 (true).\n\n";
		return;
	}

	$ROUTES_OUT->{$RID}->{_atomic} = $atomic;

	print get_time(), "INFO: Route atomic aggregator attribute for RID $RID set.\n\n";
}


# Function _cmd_route_set_aspath
sub _cmd_route_set_aspath {
	my($RID, @as_path) = (shift, @_);
	my $path = "";

	# Check RID
	check_rid($RID);

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

	# Check if aspath is valid
	foreach(@as_path) {
		if(!is_16bit($_)) {
			print get_time(), "ERROR: $_ is not a valid AS number.\n\n";
			return;
		}
		
		$path.="$_ ";
	}

	chop($path);

	$ROUTES_OUT->{$RID}->{_as_path} = $path;

	print get_time(), "INFO: Route AS path attribute for RID $RID set.\n\n";
}


# Function _cmd_route_set_community
sub _cmd_route_set_community {
	my($RID, @communities) = (shift, @_);
	my $communities = "";

	# Check RID
	check_rid($RID);

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

	# Check if aspath is valid
	foreach(@communities) {
		if(!is_community($_)) {
			print get_time(), "ERROR: $_ is not a valid community.\n\n";
			return;
		}
		
		$communities.="$_ ";
	}

	chop($communities);

	$ROUTES_OUT->{$RID}->{_communities} = $communities;

	print get_time(), "INFO: Route community attribute for RID $RID set.\n\n";
}


# Function _cmd_route_set_local_pref
sub _cmd_route_set_local_pref {
	my($RID, $local_pref) = @_;

	# Check RID
	check_rid($RID);

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

	if(!is_32bit($local_pref)) {
		print get_time(), "ERROR: $_ is not a valid local preference.\n\n";
		return;
	}

	$ROUTES_OUT->{$RID}->{_local_pref} = $local_pref;

	print get_time(), "INFO: Route local_pref attribute for RID $RID set.\n\n";
}


# Function _cmd_route_set_med
sub _cmd_route_set_med {
	my($RID, $med) = @_;

	# Check RID
	check_rid($RID);

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

	if(!is_32bit($med)) {
		print get_time(), "ERROR: $med is not a valid multi-exit discriminator.\n\n";
		return;
	}

	$ROUTES_OUT->{$RID}->{_med} = $med;

	print get_time(), "INFO: Route MED attribute for RID $RID set.\n\n";
}


# Function _cmd_route_set_net
sub _cmd_route_set_net {
	my($RID, $net) = @_;

	# Check RID
	check_rid($RID);

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

	if(!is_ipv4net($net)) {
		print get_time(), "ERROR: $net is not a valid network.\n\n";
		return;
	}

	$ROUTES_OUT->{$RID}->{_route} = ipv4_network($net);

	print get_time(), "INFO: Route network attribute for RID $RID set.\n\n";
}


# Function _cmd_route_set_nexthop
sub _cmd_route_set_nexthop {
	my($RID, $nh) = @_;

	# Check RID
	check_rid($RID);

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

	if(!is_ipv4($nh)) {
		print get_time(), "ERROR: $nh is not a valid IPv4 nexthop.\n\n";
		return;
	}

	$ROUTES_OUT->{$RID}->{_next_hop} = $nh;

	print get_time(), "INFO: Route nexthop attribute for RID $RID set.\n\n";
}


# Function _cmd_route_set_origin
sub _cmd_route_set_origin {
	my($RID, $origin) = @_;

	# Check RID
	check_rid($RID);

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

	if(!is_origin($origin)) {
		print get_time(), "ERROR: $origin is not a valid origin.\n\n";
		return;
	}

	$ROUTES_OUT->{$RID}->{_origin} = $origin;

	print get_time(), "INFO: Route origin attribute for RID $RID set.\n\n";
}


# Function _cmd_route_show
sub _cmd_route_show {
	my $RID = shift;

	print "\n", get_time(), "INFO: Route information for RID $RID:\n\n";

	if(lc($RID) eq "all") {
		foreach(keys %{$ROUTES_OUT}) {
			show_rid($_);
		}
	} elsif(defined $ROUTES_OUT->{$RID}) {
		show_rid($RID);
	} else {
		print get_time(), "ERROR: Route with RID $RID not found.\n\n";
	}
}


# Function _cmd_route_remove
sub _cmd_route_remove {
	my $RID = shift;

	# Lock $PEER_INFO
	lock($PEER_INFO);

	# Lock $ROUTES_OUT
	lock($ROUTES_OUT);

	print "\n", get_time(), "INFO: Removing route with RID $RID\n\n";

	if(lc($RID) eq "all") {
		foreach my $route (keys %{$ROUTES_OUT}) {
			next if($route =~ /^__\d+/);
			foreach(keys %{$PEER_INFO}) {
				$ROUTES_OUT->{$route}->{$_}->{_withdraw} = 1;
				$ROUTES_OUT->{$route}->{$_}->{_remove} = 1;
			}
		}
	} elsif(defined $ROUTES_OUT->{$RID}) {
		foreach(keys %{$PEER_INFO}) {
			$ROUTES_OUT->{$RID}->{$_}->{_withdraw} = 1;
			$ROUTES_OUT->{$RID}->{$_}->{_remove} = 1;
		}
	} else {
		print get_time(), "ERROR: Route with RID $RID not found.\n\n";
	}
}


# Function _cmd_show_peer
sub _cmd_show_peer {
	my $arg = shift;

	# Check if peer was already found
	my $found = 0;

        # Lock $PEER_INFO
        lock($PEER_INFO);

	if(!defined($arg)) {
		return;
	} else {
		print get_time(), "INFO: BGP peer information for peer $arg:\n\n";

		# Check peer id
		foreach (keys %{$PEER_INFO}) {
			if(lc($_) eq lc($arg)) {
				show_peer($_);
				$found++;
			}
		}

		return if $found;

		# Check remote ip and remote as
		foreach (keys %{$PEER_INFO}) {
			# Disable warnings for this block
			{
				no warnings;
				if(($PEER_INFO->{$_}->{_peer_id} eq $arg) ||
				   ($PEER_INFO->{$_}->{_peer_as} eq $arg)) {
					show_peer($_);
					$found++;
				}
			};
		}

		if(!$found) {
			print get_time(), "ERROR: BGP peer $arg not found.\n";
		}
	}

	print "\n";
}


# Function _cmd_show_peers
sub _cmd_show_peers {
        # Lock $PEER_INFO
        lock($PEER_INFO);

        # Lock $ROUTES_IN
        lock($ROUTES_IN);

	my $str = "";
	no warnings;

	print get_time(), "INFO: BGP peer summary:\n\n";
	print "Local address       : ", $Inject::CONFIG->{local}->{address}, "\n";
	print "Local AS            : ", $Inject::CONFIG->{local}->{as}, "\n";
	print "Number of peers     : ", scalar(keys %{$PEER_INFO}), "\n";
	print "Number of updates   : ", $ROUTES_IN->{_recvd_updates}?$ROUTES_IN->{_recvd_updates}:0, "\n";
	print "Number of NLRIs     : ", $ROUTES_IN->{_recvd_nlri}?$ROUTES_IN->{_recvd_nlri}:0, "\n";
	print "Number of withdrawns: ", $ROUTES_IN->{_recvd_withdrawn}?$ROUTES_IN->{_recvd_withdrawn}:0, "\n";
	print "Recvd prefixes      : ", $ROUTES_IN->{_recvd_prefixes}?$ROUTES_IN->{_recvd_prefixes}:0, "\n";
	print "Sent prefixes       : ", $ROUTES_IN->{_sent_prefixes}?$ROUTES_IN->{_sent_prefixes}:0, "\n";
	print "\n";

	print "PeerID        Neighbor        V T  AS     State         PfxRecvd    PfxSent\n";

	# Prefixes
	my $pfx_recvd = 0;
	my $pfx_sent  = 0;
	my $session_type = "";

	# Iterate over the peers
	foreach (keys %{$PEER_INFO}) {
		eval {
			$pfx_recvd = 0;
			$pfx_sent  = 0;
			$pfx_recvd = $ROUTES_IN->{$_}->{_recvd_prefixes}?$ROUTES_IN->{$_}->{_recvd_prefixes}:0;
			$pfx_sent = $ROUTES_IN->{$_}->{_sent_prefixes}?$ROUTES_IN->{$_}->{_sent_prefixes}:0;
			
			if($Inject::CONFIG->{local}->{as} == $PEER_INFO->{$_}->{_peer_as}) {
				$session_type = "I";
			} else {
				$session_type = "E";
			}
		};

		formline << 'END', $_, $PEER_INFO->{$_}->{_peer_id}, $PEER_INFO->{$_}->{_bgp_version}, $session_type, $PEER_INFO->{$_}->{_peer_as}, $PEER_INFO->{$_}->{_fsm_state}, $pfx_recvd, $pfx_sent;
@<<<<<<<<<<<< @<<<<<<<<<<<<<< @<@< @<<<<< @<<<<<<<<<<<< @<<<<<<<<<  @<<<<<<<<<
END
	
		# Some perl magic...
		$str = $^A;
		$^A = "";

		print $str;
	}

	print "\n";
}


# Function _cmd_show_routes
sub _cmd_show_routes {
	my $arg = shift;

        # Lock $ROUTES_IN
        lock($ROUTES_IN);

	# Disable warnings
	no warnings;


	my $str = "";
	my $found = 0;

	print "\nPrefix              NextHop          LPref MED       Peer          PeerID\n\n";

	foreach (keys %{$ROUTES_IN}) {
		next if(substr($_, 0, 1) eq "_");
		if($_ eq $arg || lc($arg) eq "all") {
			foreach my $prefix (keys %{$ROUTES_IN->{$_}}) {
				next if(substr($prefix, 0, 1) eq "_");
				$found = 1;

				formline << 'END', $prefix, $ROUTES_IN->{$_}->{$prefix}->{_next_hop}, $ROUTES_IN->{$_}->{$prefix}->{_local_pref}?$ROUTES_IN->{$_}->{$prefix}->{_local_pref}:0, $ROUTES_IN->{$_}->{$prefix}->{_med}?$ROUTES_IN->{$_}->{$prefix}->{_med}:0, $Inject::CONFIG->{peer}->{$_}->{address}, $_;
@<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<< @<<<< @<<<< via @<<<<<<<<<<<< / @<<<<<<<
END

				# Some perl magic...
				$str = $^A;
				$^A = "";

				print $str;
			}
		}
	}

	if($found == 0) {
		print get_time(), "ERROR: No networks in table for peer $arg.\n";
	}

	print "\n";
}


# Function _cmd_show_route
sub _cmd_show_route {
	my ($arg, $route) = (shift, shift);

        # Lock $ROUTES_IN
        lock($ROUTES_IN);

	# Disable warnings
	no warnings;

	my $str = "";
	my $found = 0;
	foreach (keys %{$ROUTES_IN}) {
		next if(substr($_, 0, 1) eq "_");
		if($_ eq $arg || lc($arg) eq "all") {
			foreach my $prefix (keys %{$ROUTES_IN->{$_}}) {
				next if(substr($prefix, 0, 1) eq "_");

				if($prefix eq $route) {
					$found = 1;
					print "\n";
					print "Network    : $prefix\n";
					print "Peer       : ", $_, "\n";
					print "Nexthop    : ", $ROUTES_IN->{$_}->{$prefix}->{_next_hop}, "\n";
					print "\n";
					print "Origin     : ", $ROUTES_IN->{$_}->{$prefix}->{_origin}, " (", map_origin($ROUTES_IN->{$_}->{$prefix}->{_origin}), ")\n";
					print "Localpref  : ", $ROUTES_IN->{$_}->{$prefix}->{_local_pref}?$ROUTES_IN->{$_}->{$prefix}->{_local_pref}:"None (EBGP)", "\n";
					print "MED        : ", $ROUTES_IN->{$_}->{$prefix}->{_med}?$ROUTES_IN->{$_}->{$prefix}->{_med}:"None", "\n";
					print "\n";
					print "Atomic agg : ", $ROUTES_IN->{$_}->{$prefix}->{_atomic_agg}?$ROUTES_IN->{$_}->{$prefix}->{_atomic_agg}:0, "\n";

					if(scalar @{$ROUTES_IN->{$_}->{$prefix}->{_aggregator}} > 0) {
						print "Aggregator : ", map($_." / ", @{$ROUTES_IN->{$_}->{$prefix}->{_aggregator}}), "\n";
					} else {
						print "Aggregator : None\n";
					}

					print "\n";
					print "AS Path    : ", map($_." ", @{$ROUTES_IN->{$_}->{$prefix}->{_as_path}}), "\n";

					if(scalar @{$ROUTES_IN->{$_}->{$prefix}->{_communities}} > 0) {
						print "Communities: ", map($_." ", @{$ROUTES_IN->{$_}->{$prefix}->{_communities}}), "\n";
					} else {
						print "Communities: None\n";
					}

					print "Attributes : ", map($_." ", @{$ROUTES_IN->{$_}->{$prefix}->{_attr_mask}}), "\n";

					print "\n";
				}
			}
		}
	}

	if($found == 0) {
		print get_time(), "ERROR: Network $route not in table.\n\n";
	}
}


# Function _cmd_show_sentroutes
sub _cmd_show_sentroutes {
	my $arg = shift;

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

        # Lock $PEER_INFO
        lock($PEER_INFO);

	my $str = "";
	my $found = 0;

	print "\nRID         S   Network              NextHop            Peer            PeerID\n\n";

	foreach (keys %{$ROUTES_OUT}) {
		foreach my $peer (keys %{$PEER_INFO}) {
			# Show routes
			if(lc($arg) eq "all" || $peer eq $arg) {
				# Check if route has all mandatory options set
				if(!$ROUTES_OUT->{$_}->{_route} ||
				   !$ROUTES_OUT->{$_}->{_next_hop} ||
				   $ROUTES_OUT->{$_}->{_origin} < 0 ||
				   $ROUTES_OUT->{$_}->{_origin} > 2) {
					print get_time(), "INFO: Ignoring route with RID $_ (missing mandatory fields)\n";
					next;
				} 

				$found = 1;

				formline << 'END', $_, $ROUTES_OUT->{$_}->{$peer}->{_injected}?"I":"N", $ROUTES_OUT->{$_}->{_route}, $ROUTES_OUT->{$_}->{_next_hop}, $Inject::CONFIG->{peer}->{$peer}->{address}, $peer;
@<<<<<<<<<  @<  @<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<< @<<<<<<<<<<<< / @<<<<<<<
END

				# Some perl magic...
				$str = $^A;
				$^A = "";

				print $str;
			}
		}
	}

	if($found == 0) {
		print get_time(), "ERROR: No networks in table for peer $arg.\n";
	}

	print "\n";
}


# Function _cmd_show_sentroute
sub _cmd_show_sentroute {
	my ($arg, $route) = (shift, shift);

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

        # Lock $PEER_INFO
        lock($PEER_INFO);

	my $str = "";
	my $found = 0;

	print "\n";

	foreach (keys %{$ROUTES_OUT}) {
		foreach my $peer (keys %{$PEER_INFO}) {
			# Show routes
			if(lc($arg) eq "all" || $peer eq $arg) {
				if($ROUTES_OUT->{$_}->{_route} eq $route) {
					# Check if route has all mandatory options set
					if(!$ROUTES_OUT->{$_}->{_route} ||
			   		   !$ROUTES_OUT->{$_}->{_next_hop}) {
						print get_time(), "INFO: Ignoring route with RID $_ (missing mandatory fields)\n";
						next;
					}

					print "\n";

					$found = 1;

					print "Route information for prefix $route:\n\n";
					print "RID        : $_\n";
					print "Injected   : ", $ROUTES_OUT->{$_}->{$peer}->{_injected}?"Yes":"No", "\n";
					print "Flapping   : ", $ROUTES_OUT->{$_}->{$peer}->{_flap}?"Yes":"No", "\n";
					print "Flap state : ", ($ROUTES_OUT->{$_}->{$peer}->{_flap_state}?$ROUTES_OUT->{$_}->{$peer}->{_flap_state}:"U")." (UP=".($ROUTES_OUT->{$_}->{$peer}->{_up_s}?$ROUTES_OUT->{$_}->{$peer}->{_up_s}:0)."/".($ROUTES_OUT->{$_}->{$peer}->{_up_s_current}?$ROUTES_OUT->{$_}->{$peer}->{_up_s_current}:0).", DOWN=".($ROUTES_OUT->{$_}->{$peer}->{_down_s}?$ROUTES_OUT->{$_}->{$peer}->{_down_s}:0)."/".($ROUTES_OUT->{$_}->{$peer}->{_down_s_current}?$ROUTES_OUT->{$_}->{$peer}->{_down_s_current}:0).")", "\n";
					print "\n";
					print "Network    : ", $ROUTES_OUT->{$_}->{_route}, "\n";
					print "\n";
					print "Peer       : $peer\n";
					print "NextHop    : ", $ROUTES_OUT->{$_}->{_next_hop}, "\n";
					print "\n";
					print "Origin     : ", $ROUTES_OUT->{$_}->{_origin}, " (", map_origin($ROUTES_OUT->{$_}->{_origin}), ")\n";
					print "Localpref  : ", $ROUTES_OUT->{$_}->{_local_pref}?$ROUTES_OUT->{$_}->{_local_pref}:0, "\n";
					print "MED        : ", $ROUTES_OUT->{$_}->{_med}?$ROUTES_OUT->{$_}->{_med}:0, "\n";
					print "\n";
					print "Atomic agg : ", $ROUTES_OUT->{$_}->{_atomic_agg}?$ROUTES_OUT->{$_}->{_atomic_agg}:0, "\n";

					if($ROUTES_OUT->{$_}->{_aggregator}->{_aggregator}) {
						print "Aggregator : ", $ROUTES_OUT->{$_}->{_aggregator}->{_aggregator}, " / AS", $ROUTES_OUT->{$_}->{_aggregator}->{_as}, "\n";
					} else {
						print "Aggregator : None\n";
					}
	
					print "\n";
					print "AS Path    : ", $ROUTES_OUT->{$_}->{_as_path}, "\n";

					print "Communities: ", $ROUTES_OUT->{$_}->{_communities}?$ROUTES_OUT->{$_}->{_communities}:"None";
					
					print "\n";
				}
			}
		}
	}

	if($found == 0) {
		print get_time(), "ERROR: No networks in table for peer $arg.\n";
	}

	print "\n";
}


# Function: _cmd_withdraw_all
sub _cmd_withdraw_all {
	my $arg = shift;

	# Disable warnings
	no warnings;

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

        # Lock $PEER_INFO
        lock($PEER_INFO);

	my $found = 0;

	foreach (keys %{$ROUTES_OUT}) {
		$found++;
		if(!$arg) {
			foreach my $peer (keys %{$PEER_INFO}) {
				if($ROUTES_OUT->{$_}->{$peer}->{_injected} == 0) {
					print get_time(), "ERROR: Can not withdraw route $_ from peer $peer, it is not injected.\n\n";
				} else {
					$ROUTES_OUT->{$_}->{$peer}->{_withdraw} = 1;
				}
			}
		} else {
			eval {
				if($ROUTES_OUT->{$_}->{$arg}->{_injected} == 0) {
					print get_time(), "ERROR: Can not withdraw RID $_ from $arg (not injected).\n\n";
				} else {
					$ROUTES_OUT->{$_}->{$arg}->{_withdraw} = 1;
				}
			};

			if($@) {
				print get_time(), "ERROR: Invalid peer $arg.\n\n";
			}
		}
	}

	if($found == 0) {
		print get_time(), "ERROR: No routes found.\n\n";
	}
}


# Function: _cmd_withdraw_rid
sub _cmd_withdraw_rid {
	my($arg, $RID) = (shift, shift);

	# Disable warnings
	no warnings;

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

        # Lock $PEER_INFO
        lock($PEER_INFO);

	foreach (keys %{$ROUTES_OUT}) {
		next if !$ROUTES_OUT->{$RID};

		if(lc($arg) eq "all") {
			foreach my $peer (keys %{$PEER_INFO}) {
				if($ROUTES_OUT->{$_}->{$peer}->{_injected} == 0) {
					print get_time(), "ERROR: Can not withdraw route $_ from peer $peer, it is not injected.\n\n";
				} else {
					$ROUTES_OUT->{$_}->{$peer}->{_withdraw} = 1;
				}
			}
		} else {
			eval {
				if($ROUTES_OUT->{$_}->{$arg}->{_injected} == 0) {
					print get_time(), "ERROR: Can not withdraw route $_ from peer $arg, it is not injected.\n\n";
				} else {
					$ROUTES_OUT->{$_}->{$arg}->{_withdraw} = 1;
				}
			};

			if($@) {
				print get_time(), "ERROR: Invalid peer $arg.\n\n";
			}
		}
	}
}


# Function: _cmd_withdraw_aggregator
sub _cmd_withdraw_aggregator {
	my($arg, $agg) = (shift, shift);

	# Disable warnings
	no warnings;

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

        # Lock $PEER_INFO
        lock($PEER_INFO);

	foreach (keys %{$ROUTES_OUT}) {
		if($ROUTES_OUT->{$_}->{_aggregator}->{_as} ne $agg &&
		   $ROUTES_OUT->{$_}->{_aggregator}->{_aggregator} ne $agg) {
			next;
		}

		if(lc($arg) eq "all") {
			foreach my $peer (keys %{$PEER_INFO}) {
				if($ROUTES_OUT->{$_}->{$peer}->{_injected} == 0) {
					print get_time(), "ERROR: Can not withdraw route $_ from peer $peer, it is not injected.\n\n";
				} else {
					$ROUTES_OUT->{$_}->{$peer}->{_withdraw} = 1;
				}
			}
		} else {
			eval {
				if($ROUTES_OUT->{$_}->{$arg}->{_injected} == 0) {
					print get_time(), "ERROR: Can not withdraw route $_ from peer $arg, it is not injected.\n\n";
				} else {
					$ROUTES_OUT->{$_}->{$arg}->{_withdraw} = 1;
				}
			};

			if($@) {
				print get_time(), "ERROR: Invalid peer $arg.\n\n";
			}
		}
	}
}


# Function: _cmd_withdraw_atomic
sub _cmd_withdraw_atomic {
	my($arg, $atomic) = (shift, shift);

	# Disable warnings
	no warnings;

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

        # Lock $PEER_INFO
        lock($PEER_INFO);

	foreach (keys %{$ROUTES_OUT}) {
		next if $ROUTES_OUT->{$_}->{_atomic} != $atomic;

		if(lc($arg) eq "all") {
			foreach my $peer (keys %{$PEER_INFO}) {
				if($ROUTES_OUT->{$_}->{$peer}->{_injected} == 0) {
					print get_time(), "ERROR: Can not withdraw route $_ from peer $peer, it is not injected.\n\n";
				} else {
					$ROUTES_OUT->{$_}->{$peer}->{_withdraw} = 1;
				}
			}
		} else {
			eval {
				if($ROUTES_OUT->{$_}->{$arg}->{_injected} == 0) {
					print get_time(), "ERROR: Can not withdraw route $_ from peer $arg, it is not injected.\n\n";
				} else {
					$ROUTES_OUT->{$_}->{$arg}->{_withdraw} = 1;
				}
			};

			if($@) {
				print get_time(), "ERROR: Invalid peer $arg.\n\n";
			}
		}
	}
}


# Function: _cmd_withdraw_aspath
sub _cmd_withdraw_aspath {
	my($arg, @as_path) = (shift, @_);

	my $as_path = join(" ", @as_path);

	# Disable warnings
	no warnings;

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

        # Lock $PEER_INFO
        lock($PEER_INFO);

	foreach (keys %{$ROUTES_OUT}) {
		next if $ROUTES_OUT->{$_}->{_as_path} ne $as_path;

		if(lc($arg) eq "all") {
			foreach my $peer (keys %{$PEER_INFO}) {
				if($ROUTES_OUT->{$_}->{$peer}->{_injected} == 0) {
					print get_time(), "ERROR: Can not withdraw route $_ from peer $peer, it is not injected.\n\n";
				} else {
					$ROUTES_OUT->{$_}->{$peer}->{_withdraw} = 1;
				}
			}
		} else {
			eval {
				if($ROUTES_OUT->{$_}->{$arg}->{_injected} == 0) {
					print get_time(), "ERROR: Can not withdraw route $_ from peer $arg, it is not injected.\n\n";
				} else {
					$ROUTES_OUT->{$_}->{$arg}->{_withdraw} = 1;
				}
			};

			if($@) {
				print get_time(), "ERROR: Invalid peer $arg.\n\n";
			}
		}
	}
}


# Function: _cmd_withdraw_community
sub _cmd_withdraw_community {
	my($arg, @communities) = (shift, @_);

	my $comm = join(" ", @communities);

	# Disable warnings
	no warnings;

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

        # Lock $PEER_INFO
        lock($PEER_INFO);

	foreach (keys %{$ROUTES_OUT}) {
		next if $ROUTES_OUT->{$_}->{_communities} ne $comm;

		if(lc($arg) eq "all") {
			foreach my $peer (keys %{$PEER_INFO}) {
				if($ROUTES_OUT->{$_}->{$peer}->{_injected} == 0) {
					print get_time(), "ERROR: Can not withdraw route $_ from peer $peer, it is not injected.\n\n";
				} else {
					$ROUTES_OUT->{$_}->{$peer}->{_withdraw} = 1;
				}
			}
		} else {
			eval {
				if($ROUTES_OUT->{$_}->{$arg}->{_injected} == 0) {
					print get_time(), "ERROR: Can not withdraw route $_ from peer $arg, it is not injected.\n\n";
				} else {
					$ROUTES_OUT->{$_}->{$arg}->{_withdraw} = 1;
				}
			};

			if($@) {
				print get_time(), "ERROR: Invalid peer $arg.\n\n";
			}
		}
	}
}


# Function: _cmd_withdraw_local_pref
sub _cmd_withdraw_local_pref {
	my($arg, $local_pref) = (shift, shift);

	# Disable warnings
	no warnings;

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

        # Lock $PEER_INFO
        lock($PEER_INFO);

	foreach (keys %{$ROUTES_OUT}) {
		next if $ROUTES_OUT->{$_}->{_local_pref} != $local_pref;

		if(lc($arg) eq "all") {
			foreach my $peer (keys %{$PEER_INFO}) {
				if($ROUTES_OUT->{$_}->{$peer}->{_injected} == 0) {
					print get_time(), "ERROR: Can not withdraw route $_ from peer $peer, it is not injected.\n\n";
				} else {
					$ROUTES_OUT->{$_}->{$peer}->{_withdraw} = 1;
				}
			}
		} else {
			eval {
				if($ROUTES_OUT->{$_}->{$arg}->{_injected} == 0) {
					print get_time(), "ERROR: Can not withdraw route $_ from peer $arg, it is not injected.\n\n";
				} else {
					$ROUTES_OUT->{$_}->{$arg}->{_withdraw} = 1;
				}
			};

			if($@) {
				print get_time(), "ERROR: Invalid peer $arg.\n\n";
			}
		}
	}
}


# Function: _cmd_withdraw_med
sub _cmd_withdraw_med {
	my($arg, $med) = (shift, shift);

	# Disable warnings
	no warnings;

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

        # Lock $PEER_INFO
        lock($PEER_INFO);

	foreach (keys %{$ROUTES_OUT}) {
		next if $ROUTES_OUT->{$_}->{_med} != $med;

		if(lc($arg) eq "all") {
			foreach my $peer (keys %{$PEER_INFO}) {
				if($ROUTES_OUT->{$_}->{$peer}->{_injected} == 0) {
					print get_time(), "ERROR: Can not withdraw route $_ from peer $peer, it is not injected.\n\n";
				} else {
					$ROUTES_OUT->{$_}->{$peer}->{_withdraw} = 1;
				}
			}
		} else {
			eval {
				if($ROUTES_OUT->{$_}->{$arg}->{_injected} == 0) {
					print get_time(), "ERROR: Can not withdraw route $_ from peer $arg, it is not injected.\n\n";
				} else {
					$ROUTES_OUT->{$_}->{$arg}->{_withdraw} = 1;
				}
			};

			if($@) {
				print get_time(), "ERROR: Invalid peer $arg.\n\n";
			}
		}
	}
}


# Function: _cmd_withdraw_nexthop
sub _cmd_withdraw_nexthop {
	my($arg, $nexthop) = (shift, shift);

	# Disable warnings
	no warnings;

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

        # Lock $PEER_INFO
        lock($PEER_INFO);

	foreach (keys %{$ROUTES_OUT}) {
		next if $ROUTES_OUT->{$_}->{_next_hop} ne $nexthop;

		if(lc($arg) eq "all") {
			foreach my $peer (keys %{$PEER_INFO}) {
				if($ROUTES_OUT->{$_}->{$peer}->{_injected} == 0) {
					print get_time(), "ERROR: Can not withdraw route $_ from peer $peer, it is not injected.\n\n";
				} else {
					$ROUTES_OUT->{$_}->{$peer}->{_withdraw} = 1;
				}
			}
		} else {
			eval {
				if($ROUTES_OUT->{$_}->{$arg}->{_injected} == 0) {
					print get_time(), "ERROR: Can not withdraw route $_ from peer $arg, it is not injected.\n\n";
				} else {
					$ROUTES_OUT->{$_}->{$arg}->{_withdraw} = 1;
				}
			};

			if($@) {
				print get_time(), "ERROR: Invalid peer $arg.\n\n";
			}
		}
	}
}


# Function: _cmd_withdraw_origin
sub _cmd_withdraw_origin {
	my($arg, $origin) = (shift, shift);

	# Disable warnings
	no warnings;

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

        # Lock $PEER_INFO
        lock($PEER_INFO);

	foreach (keys %{$ROUTES_OUT}) {
		next if $ROUTES_OUT->{$_}->{_origin} != $origin;

		if(lc($arg) eq "all") {
			foreach my $peer (keys %{$PEER_INFO}) {
				if($ROUTES_OUT->{$_}->{$peer}->{_injected} == 0) {
					print get_time(), "ERROR: Can not withdraw route $_ from peer $peer, it is not injected.\n\n";
				} else {
					$ROUTES_OUT->{$_}->{$peer}->{_withdraw} = 1;
				}
			}
		} else {
			eval {
				if($ROUTES_OUT->{$_}->{$arg}->{_injected} == 0) {
					print get_time(), "ERROR: Can not withdraw route $_ from peer $arg, it is not injected.\n\n";
				} else {
					$ROUTES_OUT->{$_}->{$arg}->{_withdraw} = 1;
				}
			};

			if($@) {
				print get_time(), "ERROR: Invalid peer $arg.\n\n";
			}
		}
	}
}


# Function: _cmd_withdraw_route
sub _cmd_withdraw_route {
	my($arg, $route) = (shift, shift);

	# Disable warnings
	no warnings;

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

        # Lock $PEER_INFO
        lock($PEER_INFO);

	foreach (keys %{$ROUTES_OUT}) {
		next if $ROUTES_OUT->{$_}->{_route} ne $route;

		if(lc($arg) eq "all") {
			foreach my $peer (keys %{$PEER_INFO}) {
				if($ROUTES_OUT->{$_}->{$peer}->{_injected} == 0) {
					print get_time(), "ERROR: Can not withdraw route $_ from peer $peer, it is not injected.\n\n";
				} else {
					$ROUTES_OUT->{$_}->{$peer}->{_withdraw} = 1;
				}
			}
		} else {
			eval {
				if($ROUTES_OUT->{$_}->{$arg}->{_injected} == 0) {
					print get_time(), "ERROR: Can not withdraw route $_ from peer $arg, it is not injected.\n\n";
				} else {
					$ROUTES_OUT->{$_}->{$arg}->{_withdraw} = 1;
				}
			};

			if($@) {
				print get_time(), "ERROR: Invalid peer $arg.\n\n";
			}
		}
	}
}


# Function: _cmd_test_sleep
sub _cmd_test_sleep {
	my $seconds = shift;

	if($TEST_DATA->{started} != 1) {
		print get_time, "ERROR: No test running, cannot sleep.\n\n";
		return;
	}

	sleep($seconds);
}


# Function: _cmd_test_waitfor
sub _cmd_test_waitfor {
	my($seconds, $regexp) = (shift, shift);

	# Reset TEST_DATA match stuff
	$TEST_DATA->{match} = 0;
	$TEST_DATA->{match_data} = '';
	$TEST_DATA->{match_line} = '';

	# Fix regexp
	$regexp =~ s/^\"//;
	$regexp =~ s/\"$//;

	# Sleep some time
	sleep($seconds);

	print $TEST_DATA->{data}, "\n";

	# Check buffer
	foreach my $line (split("\n", $TEST_DATA->{data})) {
		# Check for match
		if($line =~ /$regexp/g) {
			$TEST_DATA->{match} = 1;
			$TEST_DATA->{match_data} = $&;
			$TEST_DATA->{match_line} = $line;
			$TEST_DATA->{match_regexp} = $regexp;

			last;
		}
	}

	# Clear data buffer
	$TEST_DATA->{data} = "";
}


# Function: _cmd_test_start
sub _cmd_test_start {
	my($infile, $outfile) = (shift, shift);

	# Set autoflush
	$|=1;

	# Test counter
	my $test_cnt = 1;

	# Open inputfile
	undef($!);
	open(INFILE, "$infile");
	if($!) {
		print get_time, "ERROR: Cannot open input file \"$infile\"\n";
		print get_time, "ERROR: $!\n\n";
		return;
	}

	# Open outputfile
	undef($!);
	open(OUTFILE, ">>$outfile");
	if($!) {
		print get_time, "ERROR: Cannot open output file \"$outfile\"\n";
		print get_time, "ERROR: $!\n\n";
		return;
	}

	# Mark test as started
	$TEST_DATA->{started} = 1;

	# Capture test data
	$TEST_DATA->{capture} = 1;

	print OUTFILE "### Starting tests at ", my $tmp=localtime, "\n\n";

	# Iterate over the commands
	foreach my $line (<INFILE>) {
		next if($line=~/^\s*$/);

		if($line =~ /^\s*###/) {
			print OUTFILE $line;
			next;
		}

		print OUTFILE "### Executing command: $line\n";
		$term->process_a_cmd($line);

		if($line=~/waitfor/i) {
			print OUTFILE "#"x22, " Test start ($test_cnt) ", "#"x22, "\n";
			print OUTFILE "### Test result: ";
			if($TEST_DATA->{match} == 0) {
				print OUTFILE "FAILURE (no match)\n\n";
			} else {
				print OUTFILE "SUCCESS (match)\n\n";
				print OUTFILE "### Match line     : ",
					$TEST_DATA->{match_line}, "\n";
				print OUTFILE "### Match regexp   : ",
					$TEST_DATA->{match_regexp}, "\n";
				print OUTFILE "### Match data     : ",
					$TEST_DATA->{match_data}, "\n";
			}

			print OUTFILE "#"x22, " Test end   ($test_cnt) ", "#"x22, "\n\n\n";
			$test_cnt++;
		}
	}

	# Mark test as stopped
	$TEST_DATA->{started} = 0;

	# Don't capture test data
	$TEST_DATA->{capture} = 0;

	# Clear data buffer
	$TEST_DATA->{data} = "";

	# Close the files
	close(OUTFILE);
	close(INFILE);
}


# Show peer
sub show_peer {
	$_ = shift;

        # Lock $PEER_INFO
        lock($PEER_INFO);

	# General information
	no warnings;

	print "-------------"."-"x(length($_)), "\n";
	print "| Peer ID: $_ |\n";
	print "-------------"."-"x(length($_))."\n";
	wprint("Description      : ", $Inject::CONFIG->{peer}->{$_}->{description}, 1);
	wprint("Local address    : ", $PEER_INFO->{$_}->{_local_id}." / AS".$PEER_INFO->{$_}->{_local_as}, 1);
	wprint("Remote address   : ", $PEER_INFO->{$_}->{_peer_id}." / AS".$PEER_INFO->{$_}->{_peer_as}, 1);
	wprint("BGP Version      : ", $PEER_INFO->{$_}->{_bgp_version}, 0);
	wprint("\t\tPassive        : ", $PEER_INFO->{$_}->{_passive}, 1);
	wprint("BGP Refresh      : ", $PEER_INFO->{$_}->{_refresh}, 0);
	wprint("\t\tListen         : ", $PEER_INFO->{$_}->{_listen}, 1);
	wprint("Peer announced ID: ", $PEER_INFO->{$_}->{_peer_announced_id}, 0);
	wprint("\t\tPeer port      : ", $PEER_INFO->{$_}->{_peer_port}, 1);
	wprint("Flapping         : ", $PEER_INFO->{$_}->{_flap}==1?"Yes":"No", 0);
	wprint("\t\tFlap state     : ", ($PEER_INFO->{$_}->{_flap_state}?$PEER_INFO->{$_}->{_flap_state}:"U")." (UP=".($PEER_INFO->{$_}->{_up_s}?$PEER_INFO->{$_}->{_up_s}:0)."/".($PEER_INFO->{$_}->{_up_s_current}?$PEER_INFO->{$_}->{_up_s_current}:0).", DOWN=".($PEER_INFO->{$_}->{_down_s}?$PEER_INFO->{$_}->{_down_s}:0)."/".($PEER_INFO->{$_}->{_down_s_current}?$PEER_INFO->{$_}->{_down_s_current}:0).")", 1);;
	wprint("Connected        : ", $PEER_INFO->{$_}->{_peer_socket_connected}?"Yes":"No", 0);
	wprint("\t\tFSM state      : ", $PEER_INFO->{$_}->{_fsm_state}, 1);
	my $tmp = join(" ", $PEER_INFO->{$_}->{_event_queue});
	$tmp = "U" if($tmp=~/^\s*$/);
	wprint("Event queue      : ", $tmp, 1);
	$tmp = join(" ", $PEER_INFO->{$_}->{_message_queue});
	$tmp = "U" if($tmp=~/^\s*$/);
	wprint("Message queue    : ", $tmp, 1);

	# Buffers and timers
	wprint("Out msg buf      : ", conv($PEER_INFO->{$_}->{_out_msg_buffer}), 1);
	wprint("In msg buf       : ", conv($PEER_INFO->{$_}->{_in_msg_buffer}), 1);
	wprint("In msg buf type  : ", $PEER_INFO->{$_}->{_in_msg_buf_type}, 0);
	wprint("\t\tIn msg buf bytes exp: ", $PEER_INFO->{$_}->{_in_msg_buf_bytes_exp}, 1);
	wprint("In msg buf state : ", $PEER_INFO->{$_}->{_in_msg_buf_state}, 1);

	wprint("Peer openings    : ", $PEER_INFO->{$_}->{_open_count}, 0);
	wprint("\t\tPeer resets         : ", $PEER_INFO->{$_}->{_reset_count}, 1);
	print "\n";
	wprint("Hold timer         : ", $PEER_INFO->{$_}->{_hold_timer}, 0);
	wprint("\t\tHold time           : ", $PEER_INFO->{$_}->{_hold_time}, 1);
	wprint("Connect retry timer: ", $PEER_INFO->{$_}->{_connect_retry_timer}, 0);
	wprint("\t\tConnect retry time  : ", $PEER_INFO->{$_}->{_connect_retry_time}, 1);
	wprint("Keepalive timer    : ", $PEER_INFO->{$_}->{_keep_alive_timer}, 0);
	wprint("\t\tKeepalive time      : ", $PEER_INFO->{$_}->{_keep_alive_time}, 1);
	wprint("Peer refresh       : ", $PEER_INFO->{$_}->{_peer_refresh}, 0);
	wprint("\t\tLast timer update   : ", $PEER_INFO->{$_}->{_last_timer_update}, 1);

	print "\n";
}


# Check if RID is valid
sub check_rid {
	my $RID = shift;

	no warnings;

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

        # Lock $PEER_INFO
        lock($PEER_INFO);
	
	# Create $ROUTES_OUT object if it doesn't already exist
	if(!$ROUTES_OUT->{$RID}) {
		$ROUTES_OUT->{$RID} = &share({});
		foreach (keys %{$PEER_INFO}) {
			$ROUTES_OUT->{$RID}->{$_} = &share({});
			$ROUTES_OUT->{$RID}->{$_}->{_inject} = 0;
			$ROUTES_OUT->{$RID}->{$_}->{_injected} = 0;
			$ROUTES_OUT->{$RID}->{$_}->{_withdraw} = 0;
			$ROUTES_OUT->{$RID}->{$_}->{_flap} = 0;
			$ROUTES_OUT->{$RID}->{$_}->{PeerID} = $_;
		}

		$ROUTES_OUT->{$RID}->{_aggregator} = &share({});
		$ROUTES_OUT->{$RID}->{_aggregator}->{_as} = "";
		$ROUTES_OUT->{$RID}->{_aggregator}->{_aggregator} = "";
		$ROUTES_OUT->{$RID}->{_atomic} = 0;
		$ROUTES_OUT->{$RID}->{_communities} = "";
		$ROUTES_OUT->{$RID}->{_local_pref} = "";
		$ROUTES_OUT->{$RID}->{_med} = "";

		# Mandatory
		$ROUTES_OUT->{$RID}->{_as_path} = $Inject::CONFIG->{local}->{as};
		$ROUTES_OUT->{$RID}->{_next_hop} = "";
		$ROUTES_OUT->{$RID}->{_origin} = 0;
		$ROUTES_OUT->{$RID}->{_route} = "";
	}
}


# Set peer inject / withdraw options
sub set_peer_iw {
	my($peer, $RID) = (shift, shift);

        # Lock $ROUTES_OUT
        lock($ROUTES_OUT);

        # Lock $PEER_INFO
        lock($PEER_INFO);

	if($ROUTES_OUT->{$RID}->{$peer}->{_injected} == 1) {
		print get_time(), "Route RID $RID already injected on $peer. ";
		print "Reinjecting it.\n\n";

		$ROUTES_OUT->{$RID}->{$peer}->{_inject} = 1;
		$ROUTES_OUT->{$RID}->{$peer}->{_withdraw} = 1;
	} else {
		if($PEER_INFO->{$peer}->{_peer_socket_connected} == 1) {
			print get_time(), "Injecting RID $RID on $peer.\n\n";
		} else {
			print get_time(), "$peer down, RID $RID will be injected when peer is up.\n\n";
		}

		$ROUTES_OUT->{$RID}->{$peer}->{_inject} = 1;
	}
}


# Show route with the specified RID
sub show_rid {
	my ($RID, $peer) = (shift, shift);

	# Lock $ROUTES_OUT
	lock($ROUTES_OUT);

	print "RID        : $RID\n";
	
	if($peer) {
		print "Inject to  : $peer\n";
	}
	
	if($ROUTES_OUT->{$RID}->{_route}) {
		print "Network    : ", $ROUTES_OUT->{$RID}->{_route}, "\n";
	}

	if($ROUTES_OUT->{$RID}->{_next_hop}) {
		print "NextHop    : ", $ROUTES_OUT->{$RID}->{_next_hop}, "\n";
	}

	if($ROUTES_OUT->{$RID}->{_origin}) {
		print "Origin     : ", $ROUTES_OUT->{$RID}->{_origin}, "\n";
	}

	if($ROUTES_OUT->{$RID}->{_as_path}) {
		print "ASPath     : ", $ROUTES_OUT->{$RID}->{_as_path}, "\n";
	}

	if($ROUTES_OUT->{$RID}->{_local_pref}) {
		print "LocalPref  : ", $ROUTES_OUT->{$RID}->{_local_pref}, "\n";
	}

	if($ROUTES_OUT->{$RID}->{_med}) {
		print "MED        : ", $ROUTES_OUT->{$RID}->{_med}, "\n";
	}

	if($ROUTES_OUT->{$RID}->{_communities}) {
		print "Communities: ", $ROUTES_OUT->{$RID}->{_communities}, "\n";
	}

	if($ROUTES_OUT->{$RID}->{_aggregator}->{_aggregator}) {
		print "Aggregator : ", $ROUTES_OUT->{$RID}->{_aggregator}->{_aggregator}, " / ", $ROUTES_OUT->{$RID}->{_aggregator}->{_as}, "\n";
	}

	if($ROUTES_OUT->{$RID}->{_atomic}) {
		print "Atomic     : ", $ROUTES_OUT->{$RID}->{_atomic}, "\n";
	}

	print "\n";
}


# Set debugging options
sub set_debug {
	my ($debug, $arg, $msg) = (shift, shift, shift);

	# Lock $DEBUG
	lock($DEBUG);

	if(!$arg) {
		$DEBUG->{$debug} = 1;
		print get_time(), "INFO: Debugging of BGP $msg enabled.\n";
	} elsif($arg =~ /^off$/) {
		delete $DEBUG->{$debug};
		print get_time(), "INFO: Debugging of BGP $msg disabled.\n";
	} else {
		print get_time(), "ERROR: Invalid command args.\n";
	}

	print "\n";
}


1;
__END__

