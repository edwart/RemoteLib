package RemoteLib;
use version; $VERSION = qv('0.0.1');
use IO::Socket::INET;
use vars qw/ @INC /;
use Data::Dumper;
use Carp qw/cluck longmess shortmess/;
use File::Basename;
use English;
use FileHandle;
use Config;
use Env qw/ HTTP_PROXY HTTP_PROXY_PASS /;

use Storable qw/ freeze /;
my $topdir = $ENV{MYLOCALLIB};
if ($OSNAME =~ m/MSWin/) {
    my $localappdata = $ENV{LOCALAPPDATA};
    $localappdata =~ s!\\!/!g;
    $topdir ||= $localappdata.'/mylocallib';
}
else {
    $topdir ||= '/tmp/mylocallib';
}
our %remotelibconfig = ( server         => $ENV{REMOTELIB_SERVER} || 'miltonkeynes.pm',
                         port           => $ENV{REMOTELIB_PORT} || 7777,
                         locallib       => $ENV{REMOTELIB_DIR} || $topdir,
                         updatecheck    => $ENV{REMOTELIB_CHECK} || 'daily', 
                         with_man       => 1,
                         with_pod       => 1,
                         with_scripts   => 1,
                         debug          => 0,
                         );
my %timediffs = ( daily => (24 * 60 * 60),
                  hourly => (60 * 60),
                  everytime => 0,
                  weekly => (7 * 24 * 60 * 60),
                  monthly => (30 * 24 * 60 * 60),
                  never => -1,
                  );
our $socket = undef;
our $modlist;
warn "saving to $remotelibconfig{locallib}\n" if $remotelibconfig{debug} > 0;
mkdir($remotelibconfig{locallib}) unless -f $remotelibconfig{locallib};
our $modlistfile = "$remotelibconfig{locallib}/modlist.perl";
do $modlistfile if -f $modlistfile;
our $seen;
our $seenfile = "$remotelibconfig{locallib}/seen.perl";;
do $seenfile if -f $seenfile;
our $client = undef;
our $corelist;
my $corelistfile = "$remotelibconfig{locallib}/corelist.perl";
do $corelistfile if -f $corelistfile;
my $corelistversion = $Config{PERL_SUBVERSION} > 0
            ? sprintf("%d.%03d%03d",@Config{qw/PERL_REVISION PERL_VERSION PERL_SUBVERSION/ } )
            : sprintf("%d.%03d",@Config{qw/PERL_REVISION PERL_VERSION/ }); 
my %hash = ( PerlVersion    => join('.', @Config{qw/PERL_REVISION PERL_VERSION PERL_SUBVERSION/ }),
             archname       => $Config{archname},
             corelistversion => $corelistversion,
          );

# auto-flush on socket
$| = 1;
foreach my $subdir (qw!
						arch/auto
						arch
						lib/auto
						lib
						!) {
		unshift @INC, $remotelibconfig{locallib}."/$subdir";
}

unshift @INC, \&find_lib;
#push @INC, \&couldnt_find;

sub get_socket { 
    return $socket if $socket;
    warn Dumper \%remotelibconfig if $remotelibconfig{debug} > 1;
    $socket = IO::Socket::INET->new(
        PeerHost => $remotelibconfig{server},
        PeerPort => $remotelibconfig{port},
        Proto => 'tcp',
    );
    warn "cannot connect to the server $!\n" unless $socket;
} 

sub couldnt_find {
    my @args = @_;
    shift @args;
    my $Module = shift @args;
    return if $Module =~ m/\.al$/;
    $Module =~ s!/!::!g;
    $Module =~ s!\.pm!!;
    cluck "Couldn't find $Module\nnot in corelist and not on remotelib server\n"
}
sub find_lib { 
    my @args = @_;
    shift @args;
    my $Module = shift @args;
    $Module =~ s!/!::!g;
    $Module =~ s!\.pm!!;
    if ($seen->{$Module} and $timediffs{$config{updatecheck}} < (time() - $seen->{$Module})) {
        return;
    }
    my $fhseen = FileHandle->new("> $seenfile") or die("Can't create $seenfile: $!");
    $fhseen->print(Data::Dumper->Dump([$seen], [qw/$seen/]));
    $fhseen->close;
    my %config = (%hash, %remotelibconfig);
    $config{want_corelist} = 1 unless defined $corelist;
    return if ref $Module eq "CODE";
    $config{Module} = $Module;
    warn Dumper \%config if $remotelibconfig{debug} > 0;
    send_data(\%config);
    my $data = get_data();
    warn Dumper [ keys %{ $data->{modules} } ] if $remotelibconfig{debug} > 0;
    foreach my $mod (keys %{ $data->{modules} }) {
        $seen->{$mod} = time();
    }
    unless($corelist) {
        $corelist = $data->{corelist};
        my $fhcorelist = FileHandle->new("> $corelistfile");
        $fhcorelist->print(Data::Dumper->Dump([$corelist], [qw/$corelist/]));
        $fhcorelist->close;
    }
    $config{want_corelist} = 0;
        
    $config->{digest_hex} = $data->{digest_hex};
    mkdir $remotelibconfig{locallib} unless -d $remotelibconfig{locallib};
    if ($data->{modlist}) {
        $modlist = { %{ $data->{modlist} } };
        my $fhlist = FileHandle->new("> $modlistfile") or die("Can't create $modlistfile: $!");
        $fhlist->print(Data::Dumper->Dump([$modlist], [qw/$modlist/]));
        $fhlist->close;
    }

    while (my ($file, $contents) = each %{ $data->{files} }) {
        next if $file =~ m/^man/ and ! $remotelibconfig{with_man};
        next if $file =~ m/.pod$/ and ! $remotelibconfig{with_pod};
        next if $file =~ m/^script/ and ! $remotelibconfig{with_scripts};

        if ( $Config{archname} =~ m/MSwin/i ) {
            next if $file =~ m/^man/;
        }
        my @dirs = split("/", $file);
        my $filename = pop(@dirs);
        my $d = $remotelibconfig{locallib};
        foreach my $dir (@dirs) {
            mkdir "$d/$dir" unless -d "$d/$dir";
            $d = "$d/$dir";
        }
        unless (-d $d) {
            mkdir "$d" or warn "Can't mkdir $d: $!";
        }
        if (-d "$d/$filename") {
            next;
        }

#        print "writing $d/$filename\n";
        warn print "writing $d/$filename\n" if $remotelibconfig{debug} > 0;
        my $fh = FileHandle->new("> $d/$filename") or warn "Can't create $d/$filename : $!";
        if ($fh) {
            binmode $fh;
            $fh->print($contents);
            $fh->close;
        }
    }
    return 1;
    
}
sub send_data {
    my ($hash) = @_;
    $socket = undef;
    get_socket();
    if ($socket) {
        # data to send to a server
        my $req = Data::Dumper->Dump([$hash], [qw/$data/]);
        my $size;
        eval {
            $size = $socket->send($req);
        };
        shutdown($socket, 1);
    }

}
sub get_data {
    my $serialized = "";
    if ($socket) {
        my $data;
        do {
            $socket->recv($data, 10000);
            $serialized .= $data;
        }
        until (length $data < 1 );
        eval $serialized;
        return $data;
    }
    else {
        return undef;
    }
}
sub import {
#    warn Dumper 'import', \@_;
    my $pkg = shift;
    foreach my $conf (@_) {
        my ($key, $value) = split(/[=:]/, $conf);
        if (exists($remotelibconfig{$key})) {
            $remotelibconfig{$key} = $value;
        }
        else {
            warn "Don't recognize option $conf - ignored\n";
        }
    }
}
1;
=pod

=head1 NAME

RemoteLib - Use CPAN module without needing to install them


=head1 VERSION

This document describes RemoteLib version 0.0.1


=head1 SYNOPSIS

# On the command line

> perl -MRemoteLib <perl script>

# by setting PERL5OPT

export PERL5OPT=-MRemoteLib

# Or in your perl code

use RemoteLib;
  
  
=head1 DESCRIPTION

This module aims to make access to CPAN modules much simpler by automatically installing modules
as they are used.

It relies on the existence of a remote repository of pre-build modules in the form od PAR files.
Currently this resides on miltonkeynes.pm where over 17000 PAR files exist.

The module attempts to just do the right thing and so in most cases, all you need to do is arrange
for this module to be used and it wil just work (providing the approprale modules exist inn the remote repo.

It works by adding a code reference to the start of the @INC path and this code is called everytime a 
'use' statement is encountered and the code is passed the details.
The code cals the remote server, specifying the current architecture, perl version, module used 
amoungst other details.
The remote server checks to see if the module exists in an appropriate PAR file and if so,
extracts the file details from the PAR (PARs are in Zip format) and returns a data structure containing the contents of each file from the PAR.
In addition, the first time it is called, the server will return the list of core modules for the supplied per version.
The RemoteLib module saves each file passed back fromn th eremote server and arranges for the path to them 
to  be added to the PERL5LIB so they will be found.
The module saves information about every module downloaded so this only happens once per module

=head1 INTERFACE

 # On the command line

 > perl -MRemoteLib <perl script>

 # by setting PERL5OPT

 export PERL5OPT=-MRemoteLib

 # Or in your perl code

 use RemoteLib;

=head1 CONFIGURATION AND ENVIRONMENT

This module has several configurable settings 

=over 

=item server 

The remote server containing the PAR files - defaults to miltonkeynes.pm

=item port

The connection port to the remote server - defaults to 7777

=item locallib

The path the the top level directory where ther downloaded files will be put - the default depends on the 
operating system in use - on Windows it will use environemnt variable LOCALAPPDATA and otherwise it will use /tmp
In both cases it will use a subdirectory mylocallib

=item debug

controls how much debug out is display as follows :-

debug = 0 # no debug, the default
debug = 1 # basic debug
debug = 1 # verbose debug

=item updatecheck

Controls how long before a check for a newer version is made for a downloaded module - defaults to daily (i.e. every 24 hours)
options are everytime, hourly, daily, weekly and never

These options can be specified on the command-line as follows :-


=item with_man

controls whether to download man pages too - default to true

=item with_pod

controls whether to download pod files too - default to true

=item with_scripts

controls whether to download scripts - default to true

=back

These options cabn be specified in several ways as follows :-

=over 

=item perl -MRemoteLib=<option>=<value>,<option>=<value> # on the command line

=item PERL5OPTS="-MRemoteLib=<option>=<value>,<option>=<value>" # using PERl5OPTS

=item use RemoteLib qq!<option>=<value>,<option>=<value>!; # coded in your scripts/modules

=back 

There are also some environment variables which can controll the main options

=over

=item REMOTELIB_SERVER

specifies the server to use rather thann the default miltonkeynes.pm

=item REMOTELIB_PORT

specifies the server port to use rather thann the default 7777

=item REMOTELIB_DIR

specifies the local directory to store the downloaded files

=back 

=head1 DEPENDENCIES

None

=head1 BUGS AND LIMITATIONS

The module deliberately cannot navigate through a proxy server 

=head1 AUTHOR

Tony Edwardson tony@edwardson.co.uk

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2014, Tony Edwardson C<tony@edwardson.co.uk>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.


=cut
