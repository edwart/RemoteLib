#!/usr/bin/env perl

use strict;
use warnings;
use IO::Socket::INET;
use Data::Dumper;
use Storable qw/ nfreeze retrieve /;
use File::Slurp;
use Module::CoreList;
use File::Basename qw/  basename dirname /;
use Archive::Extract;
use PAR::Repository;
use Data::Printer;
use Carp::Always;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use Digest::SHA1 qw/sha1 sha1_hex sha1_base64/;
use Path::Tiny;
my $inventry = '/home/tony/work/inventry2.txt';
our $modules;
do $inventry;
our $pars;
my $parfiles =  '/home/tony/work/pars2.txt';
do $parfiles;
our $data;

my $socket = new IO::Socket::INET (
	LocalHost => '0.0.0.0',
	LocalPort => '7777',
	Proto => 'tcp',
	Listen => 5,
	Reuse => 1,
	) or die "Can't create socket :$!";
	print "server waiting for client connection on port 7777\n";

while(1) {
	my $client_socket = $socket->accept();
	my $client_address = $client_socket->peerhost();
    my $client_port = $client_socket->peerport();
    print "connection from $client_address:$client_port\n";
	my $recieved = "";
    # read up to 1024 characters from the connected client
    $client_socket->recv($recieved, 4096);
#	print Data::Dumper->Dump([$recieved], [qw/$received/]);
	eval $recieved;

    print "received data: ".Data::Dumper->Dump([$data], [qw/$data/]);
	my $digest_hex = sha1_hex($modules);
	my $return_data;
	$data->{digest_hex} ||= "";
	my $archname = $data->{archname};
	my %specific_modules = ( $archname => { %{ $modules->{ $data->{archname} } } },
							 any_arch  => { %{ $modules->{ any_arch } } },
							 );
	unless($data->{digest_hex} eq $digest_hex) {
		$return_data->{digest_hex} = $digest_hex;
#		$return_data->{modlist} = { %specific_modules };
		$return_data->{corelist} = $Module::CoreList::version{ $data->{corelistversion} };
	}

	
#	print Dumper $modules->{ $data->{archname} }->{ $data->{PerlVersion} }->{ $data->{Module} },
#				 $modules->{ any_arch }->{ any_version }->{ $data->{Module} }, $data;
	if (exists( $modules->{ $data->{archname} }{ $data->{PerlVersion} }->{ $data->{Module} } ) ) {
		$return_data = extract_par_to_hash( get_latest_par( $modules->{ $data->{archname} }{ $data->{PerlVersion} }->{ $data->{Module} } ), $return_data);
	}
	elsif ( exists( $modules->{ any_arch }->{ any_version }->{ $data->{Module} } ) ) {
		$return_data = extract_par_to_hash( get_latest_par( $modules->{ any_arch }{  any_version }->{ $data->{Module} } ), $return_data);
	}
	else {
		warn "Can't find ".Dumper $data->{Module};
	}
    my $size = $client_socket->send(Data::Dumper->Dump([$return_data], [qw/$data/]));
	print "sent data of size $size\n";
 
    # notify client that response has been sent
    shutdown($client_socket, 1);
}
#$socket->close();
sub extract_par_to_hash {
	my ( $par, $ret) = @_;
	my %hash = %{ $ret };
#	print Data::Dumper->Dump([ $par, $pars ], [qw/ $par $pars/]);
	my $filename = basename($par);
	my $mods = $pars->{$filename};
#	print Dumper $mods;
	$hash{modules} = { %{ $mods } };
#	print Dumper $hash{modules}; 
	my $zip = Archive::Zip->new( $par ) or die "Can't extract par $par->{path}: $!";
	foreach my $member ($zip->members()) {
		next if $member->isDirectory();
		$hash{files}{  $member->fileName } = $zip->contents( $member->fileName );
	}
	return \%hash;

}
sub get_latest_par {
	my ($pars) = @_;
	print Dumper $pars;
	my $latest_par = undef;
	my $latest_version = undef;
	foreach my $par (keys %{ $pars }) {
		$latest_par ||= $par;
		my $version = get_version($pars->{$par}, $par);
		$latest_version ||= $version;
		if ($version > $latest_version) {
			$latest_par = $par; 
			$latest_version = $version;
		}
	}
	print Data::Dumper->Dump([ $latest_par ], [qw/ $latest_par/]);

	return "/home/tony/work/$latest_par";
}
sub get_version {
	my ($version, $par) = @_;
	return $version if $version;
	my @bits = split('-', $par);
	pop(@bits);
	pop(@bits);
	my $vers = pop(@bits);
	if ($vers =~ m/^[\d.]+$/) {
		return $vers;
	}
	else {
		warn "Can't determine version $vers in $par\n";
		return 1;
	}
	return pop(@bits);
}
