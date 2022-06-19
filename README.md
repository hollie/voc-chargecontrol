# NAME

voc-chargecontrol.pl - Use the VolvoOnCall API to suspend or resume the charging of your Volvo EV. 

# SYNOPSIS

```
./voc-chargecontrol.pl [--host <MQTT server hostname...> ]

```

# DESCRIPTION

This script can either be run from the commandline for direct control or it can listen to an MQTT server to receive commands.

In direct mode, use the command:

```perl
./voc_chargecontrol.pl --voc-user ... --voc-pass ... --vin ... --location-id ... --command [active|suspend]
```

For MQTT mode, pass the MQTT server name and potentially the MQTT server username and password, together with the required VolvoOnCall parameters that are listed above.

In MQTT mode this script will listen to topic:

`voc/chargestatus`

for the commands of either `suspend` or `active`.

# Using docker to run this script in a container

This repository contains all required files to build a minimal Alpine linux container that runs the script.
The advantage of using this method of running the script is that you don't need to setup the required Perl
environment to run the script, you just bring up the container.

To do this check out this repository, configure the MQTT broker host, username, password and the required VolvoOnCall credentials in the `.env` file and run:

`docker compose up -d`.

# Updating the README.md file

The README.md file in this repo is generated from the POD content in the script. To update it, run

`pod2github bin/voc-chargecontrol.pl > README.md`

# AUTHOR

Lieven Hollevoet `hollie@cpan.org`

# LICENSE

CC BY-NC-SA
