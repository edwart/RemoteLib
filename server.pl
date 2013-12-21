#!/usr/bin/env perl

use strict;
use warnings;
use IO::Socket::INET;
use Data::Dumper;
use Storable qw/ nfreeze retrieve /;
use File::Slurp;
use Module::CoreList;
use Archive::Extract;
use PAR::Repository;
use Data::Printer;
use Carp::Always;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use Digest::SHA1 qw/sha1 sha1_hex sha1_base64/;
use Path::Tiny;
use DBM::Deep;
use File::Find::Rule;
my $libs = '/home/tony/libs';
my $pars = '/home/tony/parrepo';
my %libs = ();
=pod
my $rep = new PAR::Repository(path => $pars);
my ($dbm, $filename) = $rep->modules_dbm();
my $db = DBM::Deep->new(file=>$filename, type=>DBM::Deep->TYPE_HASH);
my $key = $db->first_key();
while ($key) {
	my $value = $db->{$key};
	my $subkey = $value->first_key();
	while($subkey) {
		my $value2 = $db->{$key}->{$subkey};
		warn( ref($value)."\n". ref($value2)."\n");
		$libs{$key}{$subkey
		print Data::Dumper->Dump([ $key,$subkey,$value, $value2], 
								 [qw/$key $subkey $value $value2/]);
		$subkey = $value->next_key($subkey);
	}
	$key = $db->next_key($key);
}
#my %modules =  %{  $modules };
#print join("\n", keys %{  $modules });
=cut
$| = 1;
my @pars = File::Find::Rule->file()->in( $pars );

foreach my $path (@pars) {
	my $orig_path = $path;
	next unless $path =~ m/\.par$/;
	$path =~ s!^$pars/!!;
	my ($arch, $perlversion, $par) = split('/', $path);
#	$libs{$arch}{$perlversion}{$par} = $par;
	$par =~ s/\.par//;
	$par =~ s/-$perlversion//;
	$par =~ s/-$arch//;
	my @bits = split('-', $par);
	my $moduleversion = pop @bits;
	my $modulename = join('::', @bits);
	$libs{$arch}{$perlversion}{$modulename} = { path => $orig_path,
												moduleversion => $moduleversion,
											 };
}
#print Dumper \%libs;
my $digest_hex = sha1_hex(\%libs);

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
 	our $data;
	my $recieved = "";
    # read up to 1024 characters from the connected client
    $client_socket->recv($recieved, 4096);
#	print Data::Dumper->Dump([$recieved], [qw/$received/]);
	eval $recieved;

#    print "received data: ".Data::Dumper->Dump([$data], [qw/$data/]);
	my $return_data = {};
	my $serialized;
	$data->{digest_hex} ||= "";
	unless($data->{digest_hex} eq $digest_hex) {
		$return_data->{digest_hex} = $digest_hex;
		$return_data->{modlist} = { %libs };
	}
	if (Module::CoreList->is_core($data->{Module}, $data->{PerlVersion})) {
		$serialized = 'Core';
	}
	else { 
		if (exists($libs{$data->{archname}}{$data->{PerlVersion}}{$data->{Module}})) {
			$serialized = extract_par_to_hash($data, $libs{$data->{archname}}{$data->{PerlVersion}}{$data->{Module}},
											  $return_data);
		}
		elsif (exists($libs{any_arch}{any_version}{$data->{Module}})) {
			$serialized = extract_par_to_hash($data, $libs{any_arch}{any_version}{$data->{Module}}, $return_data);
		}
		else {
			warn "Can't find ".Dumper $data->{archname}, $data->{PerlVersion}, $data->{Module};
		}
	}
#	else {
#		my $topdir = "$libs/$hash->{PerlVersion}/$hash->{archname}";
#		if ($libs{$topdir}) {
#			$serialized = $libs{$topdir};
#		}
#		else {
#			my @files = sort File::Find::Rule->file()->in( "$topdir" );
#			$data = {};
#			foreach my $file (@files) {
#				my $stem = $file;
#				$stem =~ s!^$topdir/!!;
#				$data->{$stem} = read_file( $file, { binmode => ':raw' });
#			}
#			# write response data to the connected client
#			print Dumper keys %{ $data };
#
#			$serialized = Data::Dumper->Dump([$data], [qw/$data/]);
#			$libs{$topdir} = $serialized;
#		}
#	}
#	print Dumper $serialized;
    my $size = $client_socket->send($serialized);
	print "sent data of size $size\n";
 
    # notify client that response has been sent
    shutdown($client_socket, 1);
}
$socket->close();
sub extract_par_to_hash {
	my ($data, $par, $ret) = @_;
	my %hash = %{ $ret };
	warn "Extracting $par->{path}\n";
	my $zip = Archive::Zip->new( $par->{path} ) or die "Can't extract par $par->{path}: $!";
	foreach my $member ($zip->members()) {
		next if $member->isDirectory();
		$hash{files}{  $member->fileName } = $zip->contents( $member->fileName );
	}
#	warn Dumper \%hash;
	return Data::Dumper->Dump([\%hash], [qw/$data/]);

}
