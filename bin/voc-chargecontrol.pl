#! /usr/bin/env perl

# PODNAME: voc-chargecontrol.pl
# ABSTRACT: Pause or resume the charging of your Volvo EV via the Volvo On Call API
# VERSION

use strict;
use warnings;

use HTTP::Request;
use LWP::UserAgent;
use Net::MQTT::Simple;
use Log::Log4perl qw(:easy);
use Getopt::Long 'HelpMessage';
use Pod::Usage;
use JSON;

my (
	$verbose,       $mqtt_host,          $mqtt_username,
	$mqtt_password, $voc_username,       $voc_password,
	$voc_vin,       $voc_chargelocation, $command
);

# Default values
$mqtt_host = 'broker';

GetOptions(
	'host=s'         => \$mqtt_host,
	'mqtt-user=s'    => \$mqtt_username,
	'mqtt-pass=s'    => \$mqtt_password,
	'voc-user=s'     => \$voc_username,
	'voc-pass=s' 	 => \$voc_password,
	'vin=s'          => \$voc_vin,
	'location-id=i'  => \$voc_chargelocation,
	'command=s'        => \$command,
	'help|?|h'       => sub { HelpMessage(0) },
	'man'            => sub { pod2usage( -exitstatus => 0, -verbose => 2 ) },
	'v|verbose'      => \$verbose,
) or HelpMessage(1);

if ($verbose) {
	Log::Log4perl->easy_init($DEBUG);
}
else {
	Log::Log4perl->easy_init($INFO);
}

# Connect to the broker if the info is passed
if ( !defined $command ) {
	my $mqtt = Net::MQTT::Simple->new($mqtt_host)
	  || die "Could not connect to MQTT broker: $!";
	INFO "MQTT logger client ID is " . $mqtt->_client_identifier();

 	# Depending if authentication is required, login to the broker
	if ( $mqtt_username and $mqtt_password ) {
		$mqtt->login( $mqtt_username, $mqtt_password );
	}
	
	# Subscribe to topics:
	my $status_topic = 'voc/chargestatus';
	my $sleep_until_topic = 'voc/sleep_until';
	
	$mqtt->subscribe( $status_topic, \&mqtt_handler );
	$mqtt->subscribe( $sleep_until_topic, \&mqtt_handler );
	
	$mqtt->run();
	
} else {
	suspend_charging($command);
	exit(0);
}


sub mqtt_handler {
	my ( $topic, $data ) = @_;

	TRACE "Got '$data' from $topic";

	if ( $topic =~ /chargestatus/ ) {
		suspend_charging($data);
		return;
	}
	
	if ($topic =~ /sleep_until/) {
		if ($data =~ /\d+\:\d{2}/) {
			INFO "Going to suspend sleep until '$data'";
			suspend_charging('suspend', $data)
		} else {
			WARN "Please pass a valid time in HH:MM format to suspend charging until that time";
		}
	}
	else {
		WARN "Invalid message received from topic " . $topic;
		return;
	}

}

sub suspend_charging {
	my $status = shift();
	my $sleep_until = shift() // '';

	DEBUG "Got command '$status'";
	
	if ( $status ne 'suspend' && $status ne 'active' ) {
		WARN "This function only supports 'suspend' or 'active' as parameters";
		return;
	}
	
	if (!defined $voc_username || !defined $voc_password || !defined $voc_vin || !defined $voc_chargelocation ) {
		ERROR "Please define voc_username, voc_password, voc_vin and voc_chargelocation as parameters to this script to be able to complete the API call";
		return;
	}

	my $headers = [
		'cache-control'     => ' no-cache',
		'content-type'      => ' application/json',
		'x-device-id'       => ' Device',
		'x-originator-type' => ' App',
		'x-os-type'         => ' Android',
		'x-os-version'      => ' 22',
	];

	my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
	  localtime();

	my $stoptime = sprintf( "%02d:%02d", $hour, 0 );
	my $starttime = sprintf( "%02d:%02d", ( $hour + 23 ) % 24, 0 );

	# In case we received a $sleep_until time ensure to override start and stoptime
	if (defined $sleep_until) {
		$starttime = $stoptime; # We need to sleep immediately
		$stoptime = $sleep_until; # Until the defined stoptime
	}

	my $body_suspend = {
		"status"                => "Accepted",
		"plugInReminderEnabled" => 'false',
		"delayCharging"         => {
			"enabled"   => 'true',
			"startTime" => $starttime,
			"stopTime"  => $stoptime
		}
	};

	my $body_continue = {
		"status"                => "Accepted",
		"plugInReminderEnabled" => 'true',
		"delayCharging"         => {
			"enabled"   => 'false',
			"startTime" => "09:00",
			"stopTime"  => "20:00"
		}
	};

	my $url =
"https://vocapi.wirelesscar.net/customerapi/rest/v3.0/vehicles/$voc_vin/chargeLocations/$voc_chargelocation";

	my $json;
	$json =
	  $status eq 'suspend'
	  ? encode_json($body_suspend)
	  : encode_json($body_continue);

	my $r = HTTP::Request->new( 'PUT', $url, $headers, $json );
	$r->authorization_basic( $voc_username, $voc_password );

	my $ua  = LWP::UserAgent->new();
	my $res = $ua->request($r);

	INFO "New mode is $status, API result code was '"
	  . $res->status_line . "'\n";

}

=head1 NAME

voc-chargecontrol.pl - Use the VolvoOnCall API to suspend or resume the charging of your Volvo EV. 

=head1 SYNOPSIS

    ./voc-chargecontrol.pl [--host <MQTT server hostname...> ]
    
=head1 DESCRIPTION

This script can either be run from the commandline for direct control or it can listen to an MQTT server to receive commands.

In direct mode, use the command:

    ./voc_chargecontrol.pl --voc-user ... --voc-pass ... --vin ... --location-id ... --command [active|suspend]

For MQTT mode, pass the MQTT server name and potentially the MQTT server username and password, together with the required VolvoOnCall parameters that are listed above.

In MQTT mode this script will listen to topic:

C<voc/chargestatus>

for the commands of either C<suspend> or C<active>.

C<voc/sleepuntil>

for a time until the car charging should be paused. Post a time in HH::MM format to this topic to start sleeping the charge process.

=head1 Using docker to run this script in a container

This repository contains all required files to build a minimal Alpine linux container that runs the script.
The advantage of using this method of running the script is that you don't need to setup the required Perl
environment to run the script, you just bring up the container.

To do this check out this repository, configure the MQTT broker host, username, password and the required VolvoOnCall credentials in the C<.env> file and run:

C<docker compose up -d>.

=head1 Updating the README.md file

The README.md file in this repo is generated from the POD content in the script. To update it, run

C<pod2github bin/voc-chargecontrol.pl E<gt> README.md>

=head1 AUTHOR

Lieven Hollevoet C<hollie@cpan.org>

=head1 LICENSE

CC BY-NC-SA

=cut
