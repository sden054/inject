# Set package
package Inject::Config;

# Version
$VERSION = $Inject::VERSION;

# Modules
use warnings;
use strict;
use base 'Inject';
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use XML::Simple;
use IO::Interface::Simple;

require Exporter;

@ISA = qw(Exporter AutoLoader);

@EXPORT = qw(load_config);
our %EXPORT_TAGS = (
	'all' => [ qw(
		load_config
		 ) ]
);


# Check configuration file
sub check_configfile {
	return(-r shift);
}


# Load configuration
sub load_config {
	my $file = shift;
	my $CONFIG = ();

	if(!check_configfile($file)) {
		return(1);
	}

	eval {
		$CONFIG = XMLin($file, ForceArray => qr/peer/);
	};

	if($@) {
		return(2, $@);
	} else {
		# Check configuration (we need at least
		# one local and one remote peer)
		if(!$CONFIG->{local}->{address} || !$CONFIG->{local}->{as}) {
			return(3, "No local ip address and/or ASN");
		}

		# Check if the local ip is valid on the system
		my $found = 0;
		
		foreach(IO::Interface::Simple->interfaces) {
			no warnings;
			if($_->address eq $CONFIG->{local}->{address}) {
				$found = 1;
				last;
			}
		}

		if($found == 0) {
			return(4, "Invalid local ip address");
		}

		# Check if we got a peer definition
		if(scalar(keys %{$CONFIG->{peer}}) == 0) {
			return(4, "No peers defined");
		}

		# Check the different peers
		foreach (keys %{$CONFIG->{peer}}) {
			if(!$CONFIG->{peer}->{$_}->{address} || !$CONFIG->{peer}->{$_}->{as}) {
				# Configuration incomplete
				return(4, "Peer $_ is missing ip address and/or ASN");
			}
		}

		# Configuration ok
		return($CONFIG);
	}
}

1;
__END__

