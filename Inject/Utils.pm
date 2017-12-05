# Set package
package Inject::Utils;

# Version
$VERSION = $Inject::VERSION;

# Modules
use warnings;
use strict;
use base 'Inject';
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use Data::Dumper;
use Socket;
use threads;
use threads::shared;
use strict 'vars';
use Data::Validate::IP qw(is_public_ipv4 is_multicast_ipv4);

require Exporter;

@ISA = qw(Exporter AutoLoader);

@EXPORT = qw(
	conv
	generate_prefix
	generate_netmask
	generate_as_path
	generate_communities
	get_time
	is_community
	is_16bit
	is_32bit
	is_ipv4
	is_ipv4net
	is_origin
	map_origin
	strip_cmd
	wprint
	ret_flap_s
	ret_rand
);

our %EXPORT_TAGS = (
	'all' => [ qw(
		conv
		generate_prefix
		generate_netmask
		generate_as_path
		generate_communities
		get_time
		is_16bit
		is_32bit
		is_community
		is_ipv4
		is_ipv4net
		is_origin
		map_origin
		strip_cmd
		wprint
		ret_flap_s
		ret_rand
		 ) ]
);


# Print method
sub wprint {
	my ($str, $arg, $nl) = (shift, shift, shift);

	$arg = "U" if(!defined $arg || $arg=~/^\s*$/);
	print $str, $arg;
	print "\n" if($nl == 1);
}


# Convert
sub conv {
	my $str = shift;
	my $tmp = "";

	for(my $i=0; $i<length($str); $i++) {
		$tmp .= sprintf("0x%02x", ord(substr($str, $i, 1)));
		$tmp .= " ";

		if($i == 10) {
			$tmp .= "...";
			last;
		}
	}

	return($tmp);
}


# Generate prefix
sub generate_prefix {
	my $ip;
	while (1) {
		$ip = int(rand(256)).".".int(rand(256)).".".int(rand(256)).".".int(rand(256));
		if(is_public_ipv4($ip) && !is_multicast_ipv4($ip)){
			return($ip);
		}
	}
	#return(int(rand(256)).".".int(rand(256)).".".int(rand(256)).".".int(rand(256)));
}


# Generate netmask
sub generate_netmask {
	return(int(rand(31))+1);
}


# Generate as path
sub generate_as_path {
	my $aspath;

	for(my $i=0; $i<int(rand(12)+1); $i++) {
		$aspath.=int(rand(65536))." ";
	}

	chop($aspath);

	if($Inject::CONFIG->{options}->{enforce_first_as} == 1) {
		$aspath = $Inject::CONFIG->{local}->{as}." ".$aspath;
	}

	return($aspath);
}


# Generate communities
sub generate_communities {
	my $communities;

	for(my $i=0; $i<int(rand(12)+1); $i++) {
		$communities.=int(rand(65536)).":".int(rand(65536))." ";
	}

	chop($communities);

	return($communities);
}



# Get time
sub get_time {
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

	use constant MONTHS => qw(
		Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dez
	);


	$mon = (MONTHS)[$mon];
	$hour = "0".$hour if(length($hour) == 1);
	$min = "0".$min if(length($min) == 1);
	$sec = "0".$sec if(length($sec) == 1);

	return("$mon $mday $hour:$min:$sec: ");
}


# Check if IPv4 address is valid
sub is_ipv4 {
	return $_[0] =~ /^[\d\.]*$/ && inet_aton($_[0]);
}


# Check if Network is valid
sub is_ipv4net {
	my $net = shift;

	if($net =~ /^\d+\.\d+\.\d+\.\d+\/\d+$/) {
		my ($ip, $nm) = split(/\//, $net);

		if(is_ipv4($ip) && ($nm > 0 && $nm < 33)) {
			# Network is valid
			return 1;
		}
	}

	return 0;
}


# Check if value is 16bit
sub is_16bit {
	return 0 if($_[0] !~ /^\d+$/);
	return 0 if($_[0] < 0 || $_[0] > 65535);
	return 1;
}


# Check if value is 32bit
sub is_32bit {
	return 0 if($_[0] !~ /^\d+$/);
	return 0 if($_[0] < 0 || $_[0] > 4294967295);
	return 1;
}


# Check if community is valid
sub is_community {
	my $community = shift;

	if($community =~ /^\d{1,5}:\d{1,5}$/) {
		my ($aaaa, $cccc) = split(/:/, $community);

		if(is_16bit($aaaa) && is_16bit($cccc)) {
			return 1;
		}
	}

	return 0;
}


# Check if origin is valid
sub is_origin {
	return $_[0] =~ /^0|1|2/;
}


# Map origin
sub map_origin {
        my $origin = shift;
        return "IGP" if $origin == 0;
        return "EGP" if $origin == 1;
        return "INCOMPLETE";
}


# Strip command
sub strip_cmd {
	my $cmd = shift;

	$cmd =~ s/^[A-z]+\(//;
	$cmd =~ s/\)$//;

	return($cmd);
}


# Return random flap value
sub ret_flap_s {
	return(int(rand(121))+1);
}


# Return random value
sub ret_rand {
	my @vals = split(/\|/, shift);

	if($#vals == 0) {
		return($vals[0]);
	} else {
		return($vals[rand($#vals+1)]);
	}
}


1;	
__END__

