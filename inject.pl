#!/usr/bin/perl

# Set package
package Inject;

# Version
$VERSION = "0.01";

###########
# Modules #
###########

use Config;

# Check for thread support and root permissions
BEGIN {
	if(!$Config{useithreads}) {
		die("Error: Please build perl with thread support.");
	}

	if($< != 0 || $) != 0) {
		die("Error: You need root permissions to run this program.");
	}
}

# Include modules
use warnings;
use strict;
use threads;
use threads::shared;
use Term::ShellUI; # Install Term::ReadLine::Perl or Term::ReadLine::GNU
use Inject::Override;
use Inject::Config;
use Inject::BGP;
use Inject::Interface;
use Inject::Utils;
use Data::Dumper;

# Set autoflush
$|=1;

# Configuration file
our $CFG_FILE = "";
if($#ARGV == 0) {
	$CFG_FILE = $ARGV[0];
} else {
	$CFG_FILE = $ENV{'HOME'}."/.inject/inject.rc";
}

# Load configuration file
our $CONFIG = ();
my $err = "";

($CONFIG, $err) = load_config($CFG_FILE);
if(!ref $CONFIG) {
	if($CONFIG == 1) {
		die("Please create a configuration file ($CFG_FILE).");
	} else {
		die("Cannot load configuration file ($CFG_FILE):\n\nError: $err\n\n");
	}
}


# Debug hash
our $DEBUG = &share({});

# Pre-define config values
$CONFIG->{prop}->{local_pref} 	= defined $CONFIG->{prop}->{local_pref}?
					  $CONFIG->{prop}->{local_pref}:2;
$CONFIG->{prop}->{med} 		= defined $CONFIG->{prop}->{med}?
					  $CONFIG->{prop}->{med}:8;
$CONFIG->{prop}->{atomic} 	= defined $CONFIG->{prop}->{atomic}?
					  $CONFIG->{prop}->{atomic}:8;
$CONFIG->{prop}->{aggregator} 	= defined $CONFIG->{prop}->{aggregator}?
					  $CONFIG->{prop}->{aggregator}:10;
$CONFIG->{prop}->{communities} 	= defined $CONFIG->{prop}->{communities}?
					  $CONFIG->{prop}->{communities}:4;

# Pre-define debug values
$DEBUG->{flap} 		= defined $CONFIG->{debug}->{flap}?
				  $CONFIG->{debug}->{flap}:1;
$DEBUG->{inject}	= defined $CONFIG->{debug}->{inject}?
				  $CONFIG->{debug}->{inject}:1;
$DEBUG->{withdraw} 	= defined $CONFIG->{debug}->{withdraw}?
				  $CONFIG->{debug}->{withdraw}:1;
$DEBUG->{open}          = defined $CONFIG->{debug}->{open}?
				  $CONFIG->{debug}->{open}:1;
$DEBUG->{reset}         = defined $CONFIG->{debug}->{reset}?
				  $CONFIG->{debug}->{reset}:1;
$DEBUG->{keepalives}    = defined $CONFIG->{debug}->{keepalives}?
				  $CONFIG->{debug}->{keepalives}:0;
$DEBUG->{refresh}       = defined $CONFIG->{debug}->{refresh}?
				  $CONFIG->{debug}->{refresh}:0;
$DEBUG->{notify}        = defined $CONFIG->{debug}->{notify}?
				  $CONFIG->{debug}->{notify}:1;
$DEBUG->{update}        = defined $CONFIG->{debug}->{update}?
				  $CONFIG->{debug}->{update}:0;
$DEBUG->{error}         = defined $CONFIG->{debug}->{error}?
				  $CONFIG->{debug}->{error}:1;

# Peer information
our $PEER_INFO = &share({});


# Route information
our $ROUTES_IN = &share({});


# Routes
our $ROUTES_OUT = &share({});

# Test data
our $TEST_DATA = &share({});

# Pre-define test data values
$TEST_DATA->{started} 		= 0;
$TEST_DATA->{capture} 		= 0;
$TEST_DATA->{match}   		= 0;
$TEST_DATA->{match_data} 	= '';
$TEST_DATA->{match_line} 	= '';
$TEST_DATA->{match_regexp} 	= '';

# Create threads
my $bgp_t 	= threads->create('Inject::BGP::bgp_t');
my $cmdline_t 	= threads->create('Inject::Interface::cmdline_t');


# Command line thread isn't so important, let
# it yield some CPU time to other threads
$cmdline_t->yield();


# Join the threads
$cmdline_t->join();
$bgp_t->join();


