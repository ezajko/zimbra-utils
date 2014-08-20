#! /usr/bin/perl

use strict;
use warnings;
use POSIX qw(strftime);
use Getopt::Long;
use Data::Dumper;

my %args = ();		# store script arguments
my %users = ();		# store zimbra users information

### SUBROUTINES
# main sub
sub main {
	init();
	createUsers();
	createCalendar();
	createMessageItems();

	# don't do any Zimbra actions if dryrun, only display data structure
	if (! $args{dryrun}) {
		zmCreateMailbox();
		zmCreateCalendar();
		zmCreateCalendarItems();
		zmCreateMessageItems();
	}
}

# retrieves and checks script arguments
sub init {
	my $opt_domain;
	my $opt_number;
	my $opt_password;
	my $opt_adminpassword;
	my $opt_verbose;
	my $opt_dryrun;
	my $opt_help;

	GetOptions(
		"d|domain=s"	=> \$opt_domain,
		"n|number=i"	=> \$opt_number,
		"p|password=s"	=> \$opt_password,
		"a|adminpassword=s"	=> \$opt_adminpassword,
		"v|verbose"	=> \$opt_verbose,
		"r|dryrun"	=> \$opt_dryrun,
		"h|help"	=> \$opt_help,
	);

	# help script argument
	$args{help} = $opt_help		if ($opt_help);
	printHelp()	if ($args{help});
	exit		if ($args{help});

	# usual script arguments
	$args{domain} = $opt_domain 	if isDomainValid($opt_domain);
	$args{number} = $opt_number 	if isNumberValid($opt_number);
	$args{password} = $opt_password	if isPasswordValid($opt_password);
	$args{adminpassword} = $opt_adminpassword	if isPasswordValid($opt_adminpassword);

	# verbose and dryrun cases
	$args{verbose} = $opt_verbose	if ($opt_verbose);
	$args{dryrun} = $opt_dryrun 	if ($opt_dryrun);
	$args{verbose} = 1		if ($args{dryrun});

}

# create users from arrays according to argument 'number'
sub createUsers {
	my @firstnames = qw(Rague TaZella Sherita Dee Zachery Tamra Albina Frankie Breanne Michelina Rosaura Thea Waltraud Sook Shyla Florentino Sol Aurelia Nicolas Jarvis Love Melia Akiko Victoria Peggie Vernell Shawnta Wally Ilse  Tosha Monte Toney Alia Brook Issac Kristyn Shawnna Gladys Colette Eliz Freda Jeremy Misha Kanesha Kassie Jordan Karry Apryl Charissa);
	my @lastnames = qw(Smith Jones Williams Brown Taylor Davies Wilson Evans Johnson Walker Wright Gerrard Robinson White Hughes Edwards Green Hall Wood Harris Lewis Martin Jackson Clark Clarke Turner Hill Scott Cooper Morris Ward Moore King Watson Baker Harrison Morgan Patel Young Allen Mitchell James Anderson Phillips Lee Bell Parker Davis);
	my $count = 0;

	LBL_CREATE_USERS:
	for my $fn (@firstnames) {
		for my $ln (@lastnames) {
			$users{$fn.'.'.$ln.'@'.$args{domain}} = {
				firstname 	=> $fn,
				lastname 	=> $ln,
				fullname	=> $fn.' '.$ln
			};
			$count++;
			last LBL_CREATE_USERS	if $count == $args{number};
		}
	}
}

# create calendar items (between 0-9) for each users
sub createCalendar {
	my $itemNumber;
	my $year = (localtime(time))[5] + 1900;
	my $count;

	# for each user, create calendar items randomly
	for my $mail (keys %users) {
		$itemNumber = int(rand(10));	# how many items ?
		$count = 1;

		while ($count <= $itemNumber) {
			push @{ $users{$mail}{calendar} }, createCalendarItem($year);
			$count++;
		}
	}
}

# return calendar instance. Some (easy) bypasses to avoid non-existent date
sub createCalendarItem {
	my ($year) = @_;
	my $startingDay = int(rand(28));	# avoid February exception
	my $startingMonth = int(rand(12));
	my $endingDay = int(rand(28));	# avoid February exception
	my $endingMonth = int(rand(12));

	if ($endingMonth == 0) {
		$endingMonth += 1;
	}

	if ($startingDay == 0) {
		$startingDay += 1;
	}

	if ($endingDay == 0) {
		$endingDay += 1;
	}

	if ($startingMonth == 0) {
		$startingMonth += 1;
	}

	while ($endingMonth <= $startingMonth) {
		$endingMonth += 1;
	}

	# format the return statement to have date range and to be ISO8601 compliant
	return $year.sprintf('%02d', $startingMonth).sprintf('%02d', $startingDay)."T000000Z-".$year.sprintf('%02d',$endingMonth).sprintf('%02d', $endingDay)."T000000Z";
}

# create message items (between 0-15) for each users with RFC-2822 compliancy
sub createMessageItems {
	my $itemNumber;
	my $count;
	my $message;
	my $date;
	my $sender;

	# for each user, create message items randomly
	for my $mail (keys %users) {
		$itemNumber = int(rand(15));	# how many items ?
		$count = 1;

		while ($count <= $itemNumber) {
			$sender = ((keys %users)[rand keys(%users)]);
			$date = strftime("%a, %d %b %Y %H:%M:%S %z", localtime(time()));	# respect RFC-2822 date format
			$message = <<EOV;
From: $sender
To: $mail
Subject: zmCreateRandomAccounts $count
Date: $date

Random mail message $count
EOV
			push @{ $users{$mail}{message} }, $message;
			$count++;
		}
	}
}

# return 1 if domain is valid. Regex should be reviewed
sub isDomainValid {
	my ($domain) = @_;
	if (!defined($domain) || $domain eq '' || $domain !~ m/^(.+)\.(.+).*/) {
		printHelp();
		die ">> ERR: -d|--domain argument is mandatory\n" if (!defined($domain));
		die ">> ERR: '$domain' is not a valid domain name\n";
	}
	return 1;
}

# return 1 if domain is valid. 
sub isNumberValid {
	my ($number) = @_;
	if (!defined($number) || $number == 0 || $number =~ m/^\D+$/ || $number !~ m/^\d+$/) {
		printHelp();
		die ">> ERR: -n|--number argument is mandatory\n"	if (!defined($number));
		die ">> ERR: '$number' is not a valid number\n";
	}
	return 1;
}

# return 1 if password is valid.
sub isPasswordValid {
	my ($password) = @_;
	if (!defined($password) || $password eq '') {
		printHelp();
		die ">> ERR: either admin or user password is not valid\n"; 
	}
	return 1;
}


# call to Zimbra mailbox creation command (should use SOAP/API call instead)
sub zmCreateMailbox {
	for my $mail (keys %users) {
		system('/opt/zimbra/bin/zmprov', 'ca', $mail, $args{password});	# TODO : use REST API
		warn ">> WARN: mailbox '$mail' was not created\n"	if ! $? == 0;
	}
}

# call to Zimbra calendar creation command (SOAP/API better)
sub zmCreateCalendar {
	my @color = qw(blue red cyan orange green yellow purple pink gray);
	for my $mail (keys %users) {
		system("zmmailbox", "-m", $mail, "-p", $args{password}, "createFolder", "--view", "appointment", "--color", $color[rand @color] ,"--flags" ,"'\#'", "/Calendar $users{$mail}{firstname}");	# TODO : use REST API
		warn ">> WARN: $mail calendar was not created\n"	if ! $? == 0;
	}
}

# call to Zimbra items calendar creation command {
sub zmCreateCalendarItems {
	my $ics;
	my $start;
	my $end;
	my $count;

	for my $mail (keys %users) {
		$count = 0;
		for my $calItem (@{ $users{$mail}{calendar} }) {
			$count++;
			$start = (split(/-/, $calItem, ))[0];
			$end = (split(/-/, $calItem, ))[1];
			$ics = <<EOV;
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//zmCreateRandomAccounts//NONSGML v1.0//EN
BEGIN:VEVENT
DTSTART:$start
DTEND:$end
SUMMARY:Random Event $count
END:VEVENT
END:VCALENDAR
EOV
			system("curl", "--user", "$mail:$args{password}", "--data", "$ics", "http://192.168.0.63/home/$mail/Calendar%20$users{$mail}{firstname}?fmt=ics");	# TODO : use curl module
		}
	}
}

# call to Zimbra message creation
sub zmCreateMessageItems {
	for my $mail (keys %users) {
		for my $message (@{ $users{$mail}{message} }) {
			system("curl", "--user", "$mail:$args{password}", "--data", "$message", "http://192.168.0.63/home/$mail/inbox/");	# TODO : use curl module
			warn ">> WARN: some messages for $mail cannot be created\n"	if ! $? == 0;
		}
	}
}

# print the helping message
sub printHelp {
	print <<EOT;
This script is used to create a random data structure which represents Zimbra user accounts with random Zimbra items (Calendar, Task, Message, Contact, etc.).
Then, it creates those objects into Zimbra instance.

Usage: zmCreateRandomAccounts.pl -d|--domain <domain> -n|--number <number> -p|--password <password> -a|--adminpassword <adminPassword> -u|--url <url> [-s|--ssl] [-r|--drynrun] [-v|--verbose] [-h|--help] 

Options:
 -d, --domain
    Set the domain name for accounts
 -n, --number
    How many accounts do you want to be created ?
 -p, --password
    Set the password for each created account
 -a, --adminpassword
    Set the admin password to create Zimbra items
 -u, --url
    Set the Zimbra URL (not yet implemented)
 -s, --ssl
    Secure transactions (not yet implemented)
 -v, --verbose
    Display the data structure 
 -r, --dryrun
    Implicit --verbose AND does not execute any Zimbra actions
 -h, --help
    Print detailed help screen

EOT
}

### CORE
main();

### DEBUG
print Dumper(\%users)	if $args{verbose};

__END__
