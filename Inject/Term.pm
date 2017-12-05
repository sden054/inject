# Set package
package Inject::Term;

# Version
$VERSION = $Inject::VERSION;

# Modules
use warnings;
use strict;
use base 'Inject';
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use Inject::Interface ();
use Term::ShellUI;
use threads;
use threads::shared;

require Exporter;

@ISA = qw(Exporter AutoLoader);

@EXPORT = qw(
	term
);

our %EXPORT_TAGS = (
	'all' => [ qw(
		term
		 ) ]
);


# Function term
sub term {
	package Inject::Interface;

	# Documentation
	my $_doc_history =
"
Usage: history -c -d NUM

Specify a number to list the last N lines of history. Pass -c to clear
the command history, -d NUM to delete a single history item.

";

	my $_doc_help =
"
Usage: help <arg>
Alias: h <arg> | ? <arg>

This command shows command usages and explanations.

Example: help show peers

";

	my $_doc_exit =
"
Usage: exit
Alias: quit | <CTRL-C>

This command closes all open BGP sessions, terminates all threads and exits
the program.

";
	
	my $_doc_debug_all =
"
Usage: debug all <off>

This command enables / disables debugging output of all possible
features.

Warning: It can produce A LOT of console output, use with caution.

";

	my $_doc_debug_flap =
"
Usage: debug flap <off>
Default: Yes

This command enables / disables debugging of BGP session and route flaps.

";

	my $_doc_debug_inject =
"
Usage: debug inject <off>
Default: Yes

This command enables / disables debugging of route injections.

";

	my $_doc_debug_withdraw =
"
Usage: debug withdraw <off>
Default: Yes

This command enables / disables debugging of route withdraws.

";

	my $_doc_debug_open =
"
Usage: debug open <off>
Default: Yes

This command enables / disables debugging of BGP session openings.

";

	my $_doc_debug_reset =
"
Usage: debug reset <off>
Default: Yes

This command enables / disables debugging of BGP session resets.

";

	my $_doc_debug_keepalives =
"
Usage: debug keepalives <off>
Default: No

This command enables / disables debugging of BGP keepalive packets.

Warning: It can produce a lot of console output, use with caution.

";

	my $_doc_debug_refresh =
"
Usage: debug refresh <off>
Default: No

This command enables / disables debugging of BGP refresh packets.

";

	my $_doc_debug_notify =
"
Usage: debug notify <off>
Default: Yes

This command enables / disables debugging of BGP notification packets.

";

	my $_doc_debug_update =
"
Usage: debug update <detail|off>
Default: No

This command enables / disables debugging of BGP update packets.

Warning: It can produce a lot of console output, use with caution.

";

	my $_doc_debug_error =
"
Usage: debug error <off>
Default: Yes

This command enables / disables debugging of BGP error packets.

";

	my $_doc_inject =
"
Usage: inject <peerid|all> <rid>

This command injects the route with the corresponding route id (rid)
on the peer with the specified peerid. If the route should be injected on all
peers use \"all\" as the peerid.

The route must have all mandatory parameters (network, nexthop, origin)
set, otherwise the route will not be injected and an error will be thrown.

If the route was already injected, the old route will be withdrawn and it 
will be injected again.

";

	my $_doc_generate_routes =
"
Usage: generate routes <peerid|all> <number of routes> <args1>...<argsN>

This command generates a number of specified random routes. The routes will
be injected on the specified peer(s).

BGP attributes which should not be random can be specified in the following
way:

	generate routes all 100 nexthop(100.0.0.1|200.0.0.1) origin(1)

This generates 100 routes with random values, except the nexthop will be
100.0.0.1 or 200.0.0.1 and the origin will always be 1.

Valid arguments are:

	flap(0-100) 			  -> Percent of routes which should flap
					     Flap time is between 1 and 120 secs
	nexthop(<nh1>|...) 		  -> Nexthops
	origin(0|1|2) 			  -> Origin
	localpref(<l1>|...)	 	  -> LocalPref
	med(<med1>|...) 		  -> Multi-exit discriminator (MED)
	atomic(0|1) 			  -> Atomic aggregate
	aggregator(<asn1:agg1>|...) 	  -> Aggregator
	aspath(<as1,as2>|...) 		  -> AS Path
	community(<aa1:dd1,aa2:dd2>|...)  -> Communities

";

	my $_doc_generate_remove =
"
Usage: generate remove

This commands removes all generated routes.

";

	my $_doc_flap_peer =
"
Usage: flap peer <peerid|all> <up seconds> <down seconds>

This command enables peer flapping. \"Up seconds\" will be decremented every
second and the peer will be stopped when a value of 0 has been reached.
After that, \"down seconds\" will be decremented every second and if a value
of 0 has been reached, the peer will be reenabled for another \"up seconds\"
seconds.

";

	my $_doc_flap_route =
"
Usage: flap route <peerid|all> <rid> <up seconds> <down seconds>

This command enables route flapping of the specified rid. \"Up seconds\" will
be decremented every seconds and the route will be withdrawn when a value
of 0 has been reached. After that, \"down seconds\" will be decremented every
second and if a value of 0 has been reached, the route will be readvertised
to the specified peer for another \"up seconds\" seconds.

";

	my $_doc_unflap_peer =
"
Usage: unflap peer <peerid|all>

This command stops peer flapping. The peer will remain in the last state.

";

	my $_doc_unflap_route =
"
Usage: unflap route <peerid|all> <rid>

This command stops route flapping for the specified route. The route will
remain in the last state.

";

	my $_doc_peer_start =
"
Usage: peer start <peerid|all>

This command starts a BGP peer and establishes a peering session.

";

	my $_doc_peer_stop =
"
Usage: peer stop <peerid|all>

This command stops a BGP peer and closes the peering session.

";

	my $_doc_route_aggregator =
"
Usage: route aggregator <rid> <asn> <aggregator ip>
Default  : None
Mandatory: No

This command sets the BGP aggregator path attribute. The first argument is
the route id (rid), the second argument is the ASN of the route aggregator and
the third argument is the aggregator's IPv4 address in dotted-decimal
notation.

";

	my $_doc_route_atomic =
"
Usage: route atomic <rid> <0|1>
Default  : None
Mandatory: No

This command corresponds to the ATOMIC_AGGREGATE path attribute. It is a
boolean value and may be omitted, in which case no ATOMIC_AGGREGATE path
attribute will be sent.

";

	my $_doc_route_aspath =
"
Usage: route aspath <rid> <as1>...<asN>
Default  : Local AS
Mandatory: Yes

This command sets the AS_PATH path attribute. The path consits of one or more
16bit AS numbers.

";

	my $_doc_route_community =
"
Usage: route community <rid> <community1>...<communityN>
Default  : None
Mandatory: No

This command corresponds to the COMMUNITIES attribute. The communities are
encoded in a special format: AAAA:CCCC, where AAAA is the AS number and CCCC
the community id (both are 16bit unsigned values).

";

	my $_doc_route_local_pref =
"
Usage: route localpref <rid> <localpref>
Default  : None
Mandatory: No

This command sets the LOCAL_PREF path attribute. It is expressed as a 32bit
unsigned number and may be omitted.

";
	
	my $_doc_route_med =
"
Usage: route med <rid> <med>
Default  : None
Mandatory: No

This command sets the MULTI_EXIT_DISC path attribute (MED). It is expressed 
as a 32bit unsigned number and may be omitted.

";

	my $_doc_route_nexthop =
"
Usage: route nexthop <rid> <nexthop>
Default  : None
Mandatory: Yes

This command sets the NEXT-HOP path attribute. It is expressed as a
dotted decimal IPv4 address and can not be omitted. If a route without
a next hop will be injected, it will produce an error and the route
will not be injected.

";

	my $_doc_route_origin =
"
Usage: route origin <rid> <1|2|3>
Default  : 2 (INCOMPLETE)
Mandatory: Yes

This command sets the ORIGIN path attribute. It is expressed as an integer
value. The following values are valid:

   0  => IGP
   1  => EGP
   2  => INCOMPLETE

If no origin is set, a default value of 3 (INCOMPLETE) will be used.

";

	my $_doc_route_net =
"
Usage: route net <rid> <network>
Default  : None
Mandatory: Yes

This command sets the network (route) which will be announced to the BGP peers.
It is expressed as a dotted decimal IPv4 address followed by a netmask and
is mandatory.

Example: route net 1 10.0.0.0/24

";

	my $_doc_route_show =
"
Usage: route show <rid|all>

This commands shows detailed information about the route with the specified
rid.

";

	my $_doc_route_remove =
"
Usage: route remove <rid|all>

This command removes the route with the specified rid. If the route is 
currently injected, it will be withdrawn before.

";

	my $_doc_show_config =
"
Usage: show config

This command prints the name of the configuration file and the
current configuration.

";

	my $_doc_show_debug =
"
Usage: show debug <arg>

This command shows the enabled debugging optione.

";

	my $_doc_show_peer =
"
Usage: show peer <peerid|ip address|remote as>

This command shows information about active and inactive BGP peers.

";

	my $_doc_show_peers =
"
Usage: show peers

This command shows summary information about active and inactive BGP peers.

";

	my $_doc_show_routes =
"
Usage: show routes <peerid|all>

This command shows summary information about received routes from the
specified BGP peer.

";

	my $_doc_show_route =
"
Usage: show route <peerid|all> <route>

This command shows detailed information about a received route from
the specified BGP peer.

";

	my $_doc_show_sentroutes =
"
Usage: show sentroutes <peerid|all>

This command shows summary information about sent routes to the specified
BGP peer.

";

	my $_doc_show_sentroute =
"
Usage: show sentroute <peerid|all> <route>

This command shows detailed information about sent routes to the
specified BGP peer.

";

	my $_doc_withdraw_all =
"
Usage: withdraw all (<peerid>)
Default: All peers

This command withdraws all routes or all routes advertised to a specific peer.

";

	my $_doc_withdraw_rid =
"
Usage: withdraw rid <peerid|all> <rid>

This command withdraws the route matching rid from the specified peer.

";

	my $_doc_withdraw_aggregator =
"
Usage: withdraw aggregator <peerid|all> <asn|ip>

This command withdraws all routes matching the ASN or the IPv4 address 
of the aggregator from the specified peer.

";

	my $_doc_withdraw_atomic =
"
Usage: withdraw atomic <peerid|all> <0|1>

This command withdraws all routes matching the atomic aggregator attribute
from the specified peer.

";

	my $_doc_withdraw_aspath =
"
Usage: withdraw aspath <peerid|all> <as1>...<asN>

This command withdraws all routes matching the AS path from the specified
peer.

";

	my $_doc_withdraw_community =
"
Usage: withdraw community <peerid|all> <community1>...<communityN>

This command withdraws all routes matching the community from the specified
peer.

";

	my $_doc_withdraw_local_pref =
"
Usage: withdraw localpref <peerid|all> <localpref>

This command withdraws all routes matching the localpref from the specified
peer.

";

	my $_doc_withdraw_med =
"
Usage: withdraw med <peerid|all> <med>

This command withdraws all routes matching the multi-exit discriminator (MED)
from the specified peer.

";

	my $_doc_withdraw_nexthop =
"
Usage: withdraw nexthop <peerid|all> <nexthop>

This command withdraws all routes matching the next-hop from the specified
peer.

";

	my $_doc_withdraw_origin =
"
Usage: withdraw origin <peerid|all> <origin>

This command withdraws all routes matching the origin from the specified
peer.

";

	my $_doc_withdraw_route =
"
Usage: withdraw route <peerid|all> <route/nm>

This command withdraws all routes matching the network from the specified
peer.

";

	my $_doc_test_start =
"
Usage: test start <testfile> <outputfile>

This command runs tests on the specified commands in the testfile an produces
an outputfile.

";

	my $_doc_test_waitfor =
"
Usage: test waitfor <seconds> \"<regexp>\"

This command waits the specified seconds and tests, if the output of one of
the previous commands matches the regular expression.

Info: All backslashes in the regular expression have to be quoted, for example
if you want to match \"foo    bar\", you have to do something like this:

test waitfor 2 \"foo\\\\s+bar\"

";

	my $_doc_test_sleep =
"
Usage: sleep <seconds>

Sleeps for the specified seconds. Output from the BGP thread still gets
captured.

";

	# Create term
	my $term = new Term::ShellUI(
		# Set history file
		history_file 	=> $Inject::CONFIG->{historyfile} ?
				   $Inject::CONFIG->{historyfile} :
				   '',

		# Set maximum history lines
		history_max 	=> $Inject::CONFIG->{history_max} ?
				   $Inject::CONFIG->{history_max} :
				   500,

		# Set prompt
		prompt 		=> $Inject::CONFIG->{prompt} ?
				   $Inject::CONFIG->{prompt} :
				   "Inject> ",

		# Keep quotes
		keep_quotes 	=> 1,

		# Commands
		commands 	=> {
			# Default handler for history
			"" => { args => sub { shift->complete_history(@_) } },

			# History
			"history" => {
				desc => "Prints the command history",
				args => "[-c] [-d] [number]",
				doc => $_doc_history,
				method => sub { shift->history_call(@_) },
			},
			
			# Help
			"help" => {
				desc => "Help",
				doc  => $_doc_help,
				method => sub { shift->help_call(undef, @_); }
			},

			# h (Help alias)
			"h" => {
				alias => "help",
			},

			# ? (Help alias)
			"?" => {
				alias => "help",
			},

			# Exit
			"exit" => {
				desc => "Exit program",
				doc  => $_doc_exit,
				maxargs => 0,
				proc => \&_cmd_exit,
			},

			# Quit (Exit alias)
			"quit" => {
				alias => "exit",
			},

			# Debug
			"debug" => {
				desc => "Debugging options",
				cmds => {
					# Set all debugging options
					"all" => {
						desc => "Debug all",
						doc  => $_doc_debug_all,
						maxargs => 1,
						proc => \&_cmd_debug_all,
					},
					# Debug BGP session and route flaps
					"flap" => {
						desc => "Debug BGP session and route flaps",
						doc => $_doc_debug_flap,
						maxargs => 1,
						proc => \&_cmd_debug_flap
					},
					# Debug BGP route injections
					"inject" => {
						desc => "Debug BGP route injections",
						doc => $_doc_debug_inject,
						maxargs => 1,
						proc => \&_cmd_debug_inject
					},
					# Debug BGP route withdraws
					"withdraw" => {
						desc => "Debug BGP route withdraws",
						doc => $_doc_debug_withdraw,
						maxargs => 1,
						proc => \&_cmd_debug_withdraw
					},
					# Debug BGP open packets
					"open" => {
						desc => "Debug BGP session openings",
						doc => $_doc_debug_open,
						maxargs => 1,
						proc => \&_cmd_debug_open,
					},

					"reset" => {
						desc => "Debug BGP session resets",
						doc => $_doc_debug_reset,
						maxargs => 1,
						proc => \&_cmd_debug_reset,
					},

					"keepalives" => {
						desc => "Debug BGP keepalives",
						doc => $_doc_debug_keepalives,
						maxargs => 1,
						proc => \&_cmd_debug_keepalives,
					},

					"refresh" => {
						desc => "Debug BGP refreshs",
						doc => $_doc_debug_refresh,
						maxargs => 1,
						proc => \&_cmd_debug_refresh,
					},

					"notify" => {
						desc => "Debug BGP notifications",
						doc => $_doc_debug_notify,
						maxargs => 1,
						proc => \&_cmd_debug_notify,
					},

					"update" => {
						desc => "Debug BGP updates",
						doc => $_doc_debug_update,
						maxargs => 1,
						proc => \&_cmd_debug_update,
					},

					"error" => {
						desc => "Debug BGP errors",
						doc => $_doc_debug_error,
						maxargs => 1,
						proc => \&_cmd_debug_error,
					},
				},
			},

			# Flap peers and routes
			"flap" => {
				desc => "Flap peers and routes",
				cmds => {
					# Flap peer
					"peer" => {
						desc => "Flap peer",
						doc => $_doc_flap_peer,
						minargs => 3,
						maxargs => 3,
						proc => \&_cmd_flap_peer,
					},
					# Flap route
					"route" => {
						desc => "Flap route",
						doc => $_doc_flap_route,
						minargs => 4,
						maxargs => 4,
						proc => \&_cmd_flap_route,
					},
				},
			},

			# Unflap peers and routes
			"unflap" => {
				desc => "Unflap peers and routes",
				cmds => {
					# Flap peer
					"peer" => {
						desc => "Unflap peer",
						doc => $_doc_unflap_peer,
						minargs => 1,
						maxargs => 1,
						proc => \&_cmd_unflap_peer,
					},
					# Unflap route
					"route" => {
						desc => "Unflap route",
						doc => $_doc_unflap_route,
						minargs => 2,
						maxargs => 2,
						proc => \&_cmd_unflap_route,
					},
				},
			},

			# Inject route
			"inject" => {
				desc => "Inject routes",
				doc => $_doc_inject,
				minargs => 2,
				maxargs => 2,
				proc => \&_cmd_inject,
			},

			# Generate random routes
			"generate" => {
				desc => "Generate random routes",
				cmds => {
					# Generate random routes
					"routes" => {
						desc => "Generate random routes",
						doc => $_doc_generate_routes,
						minargs => 2,
						proc => \&_cmd_generate_routes
					},
					# Remove all generated routes
					"remove" => {
						desc => "Remove all generated routes",
						doc => $_doc_generate_remove,
						maxargs => 0,
						proc => \&_cmd_generate_remove
					},
				},
			},

			# Start / stop peer
			"peer" => {
				desc => "Start / stop peers",
				cmds => {
					# Start peer
					"start" => {
						desc => "Start peer",
						doc => $_doc_peer_start,
						minargs => 1,
						maxargs => 1,
						proc => \&_cmd_peer_start
					},
					# Stop peer
					"stop" => {
						desc => "Stop peer",
						doc => $_doc_peer_stop,
						minargs => 1,
						maxargs => 1,
						proc => \&_cmd_peer_stop
					},
				},
			},

			# Set route options
			"route" => {
				desc => "Set route options",
				cmds => {
					# Set aggregator
					"aggregator" => {
						desc => "Set aggregator",
						doc => $_doc_route_aggregator,
						minargs => 3,
						maxargs => 3,
						proc => \&_cmd_route_set_agg
					},
					# Set atomic aggregate
					"atomic" => {
						desc => "Set atomic aggregate",
						doc => $_doc_route_atomic,
						minargs => 2,
						maxargs => 2,
						proc => \&_cmd_route_set_atomic
					},
					# Set as path
					"aspath" => {
						desc => "Set AS path",
						doc => $_doc_route_aspath,
						minargs => 2,
						proc => \&_cmd_route_set_aspath
					},
					# Set community
					"community" => {
						desc => "Set community",
						doc => $_doc_route_community,
						minargs => 2,
						proc => \&_cmd_route_set_community
					},
					# Set localpref
					"localpref" => {
						desc => "Set local preference",
						doc => $_doc_route_local_pref,
						minargs => 2,
						maxargs => 2,
						proc => \&_cmd_route_set_local_pref
					},
					# Set multi-exit discriminator (MED)
					"med" => {
						desc => "Set multi-exit discriminator (MED)",
						doc => $_doc_route_med,
						minargs => 2,
						maxargs => 2,
						proc => \&_cmd_route_set_med
					},
					# Set network
					"net" => {
						desc => "Set network (route)",
						doc => $_doc_route_net,
						minargs => 2,
						maxargs => 2,
						proc => \&_cmd_route_set_net
					},
					# Set nexthop
					"nexthop" => {
						desc => "Set nexthop",
						doc => $_doc_route_nexthop,
						minargs => 2,
						maxargs => 2,
						proc => \&_cmd_route_set_nexthop
					},
					# Set origin
					"origin" => {
						desc => "Set origin",
						doc => $_doc_route_origin,
						minargs => 2,
						maxargs => 2,
						proc => \&_cmd_route_set_origin
					},
					# Show route
					"show" => {
						desc => "Show generated route",
						doc => $_doc_route_show,
						minargs => 1,
						maxargs => 1,
						proc => \&_cmd_route_show
					},
					# Remove route
					"remove" => {
						desc => "Remove generated route",
						doc => $_doc_route_remove,
						minargs => 1,
						maxargs => 1,
						proc => \&_cmd_route_remove
					},
				},
			},

			# Show commands
			"show" => {
				desc => "Show commands",
				cmds => {
					# Show configuration
					"config" => {
						desc => "Show configuration",
						doc  => $_doc_show_config,
						maxargs => 0,
						proc => \&_cmd_show_config,
					},
					# Show debugging
					"debug" => {
						desc => "Show debugging",
						doc  => $_doc_show_debug,
						maxargs => 1,
						proc => \&_cmd_show_debug,
					},
					# Show peer
					"peer" => {
						desc => "Show BGP peer",
						doc  => $_doc_show_peer,
						minargs => 1,
						maxargs => 1,
						proc => \&_cmd_show_peer
					},
					# Show peers
					"peers" => {
						desc => "Show BGP peers",
						doc  => $_doc_show_peers,
						minargs => 0,
						maxargs => 0,
						proc => \&_cmd_show_peers
					},
					# Show routes
					"routes" => {
						desc => "Show routes",
						doc => $_doc_show_routes,
						minargs => 1,
						maxargs => 1,
						proc => \&_cmd_show_routes
					},
					# Show route (detailed)
					"route" => {
						desc => "Show detailed route",
						doc => $_doc_show_route,
						minargs => 2,
						maxargs => 2,
						proc => \&_cmd_show_route
					},
					# Show sent routes
					"sentroutes" => {
						desc => "Show sent routes",
						doc => $_doc_show_sentroutes,
						minargs => 1,
						maxargs => 1,
						proc => \&_cmd_show_sentroutes
					},
					# Show sent route (detailed)
					"sentroute" => {
						desc => "Show detailed sent route",
						doc => $_doc_show_sentroute,
						minargs => 2,
						maxargs => 2,
						proc => \&_cmd_show_sentroute
					},
				},
			},

			# Withdraw routes
			"withdraw" => {
				desc => "Withdraw routes",
				cmds => {
					# Withdraw all routes
					"all" => {
						desc => "Withdraw all routes",
						doc => $_doc_withdraw_all,
						minargs => 0,
						maxargs => 1,
						proc => \&_cmd_withdraw_all
					},
					# Withdraw routes matching rid
					"rid" => {
						desc => "Withdraw routes matching rid",
						doc => $_doc_withdraw_rid,
						minargs => 2,
						maxargs => 2,
						proc => \&_cmd_withdraw_rid
					},
					# Withdraw routes matching aggregtor
					"aggregator" => {
						desc => "Withdraw routes matching aggregator",
						doc => $_doc_withdraw_aggregator,
						minargs => 2,
						maxargs => 2,
						proc => \&_cmd_withdraw_aggregator
					},
					# Withdraw routes matching atomic aggregator
					"atomic" => {
						desc => "Withdraw routes matching atomic aggregator",
						doc => $_doc_withdraw_atomic,
						minargs => 2,
						maxargs => 2,
						proc => \&_cmd_withdraw_atomic,
					},
					# Withdraw routes matching aspath
					"aspath" => {
						desc => "Withdraw routes matching aspath",
						doc => $_doc_withdraw_aspath,
						minargs => 2,
						proc => \&_cmd_withdraw_aspath,
					},
					# Withdraw routes matching community
					"community" => {
						desc => "Withdraw routes matching community",
						doc => $_doc_withdraw_community,
						minargs => 2,
						proc => \&_cmd_withdraw_community
					},
					# Withdraw routes matching localpref
					"localpref" => {
						desc => "Withdraw routes matching localpref",
						doc => $_doc_withdraw_local_pref,
						minargs => 2,
						maxargs => 2,
						proc => \&_cmd_withdraw_local_pref
					},
					# Withdraw routes matching MED
					"med" => {
						desc => "Withdraw routes matching MED",
						doc => $_doc_withdraw_med,
						minargs => 2,
						maxargs => 2,
						proc => \&_cmd_withdraw_med
					},
					# Withdraw routes matching nexthop
					"nexthop" => {
						desc => "Withdraw routes matching nexthop",
						doc => $_doc_withdraw_nexthop,
						minargs => 2,
						maxargs => 2,
						proc => \&_cmd_withdraw_nexthop
					},
					# Withdraw routes matching origin
					"origin" => {
						desc => "Withdraw routes matching origin",
						doc => $_doc_withdraw_origin,
						minargs => 2,
						maxargs => 2,
						proc => \&_cmd_withdraw_origin
					},
					# Withdraw routes matching network
					"route" => {
						desc => "Withdraw routes matching network",
						doc => $_doc_withdraw_route,
						minargs => 2,
						maxargs => 2,
						proc => \&_cmd_withdraw_route
					}
				}
			},

			# Test
			"test" => {
				desc => "Test commands",
				cmds => {
					# Start test
					"start" => {
						desc => "Start test",
						doc  => $_doc_test_start,
						minargs => 2,
						maxargs => 2,
						proc => \&_cmd_test_start,
					},
					# Waitfor regexp
					"waitfor" => {
						desc => "Waitfor regexp",
						doc  => $_doc_test_waitfor,
						minargs => 2,
						maxargs => 2,
						proc => \&_cmd_test_waitfor,
					},
					# Sleep
					"sleep" => {
						desc => "Sleep some time",
						doc  => $_doc_test_sleep,
						minargs => 1,
						maxargs => 1,
						proc => \&_cmd_test_sleep,
					}
				}
			}
		}
	);

	return($term);
}

1;
__END__

