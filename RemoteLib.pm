#package RemoteLib;
use IO::Socket::INET;
#use File::HomeDir;
use vars qw/ @INC /;
use Data::Dumper;
use Carp qw/cluck longmess shortmess/;
use File::Basename;
use English;
use FileHandle;
use Config;
use Env qw/ HTTP_PROXY HTTP_PROXY_PASS /;

use Storable qw/ freeze /;
my $server = shift;
our $socket = undef;
our $modlist;
our $topdir = $ENV{MYLOCALLIB};
if ($OSNAME =~ m/MSWin/) {
    my $localappdata = $ENV{LOCALAPPDATA};
    $localappdata =~ s!\\!/!g;
    $topdir ||= $localappdata.'/mylocallib';
}
else {
    $topdir ||= '/tmp/mylocallib';
}
warn "saving to $topdir\n";
mkdir($topdir) unless -f $topdir;
our $modlistfile = "$topdir/modlist.perl";
do $modlistfile if -f $modlistfile;
our $seen;
our $seenfile = "$topdir/seen.perl";;
do $seenfile if -f $seenfile;
our $client = undef;
my %hash = ( PerlVersion    => join('.', @Config{qw/PERL_REVISION PERL_VERSION PERL_SUBVERSION/ }),
             archname       => $Config{archname},
          );

# auto-flush on socket
$| = 1;
foreach my $subdir (qw!
						arch/auto
						arch
						lib/auto
						lib
						!) {
		unshift @INC, "$topdir/$subdir";
}

unshift @INC, \&find_lib;

sub get_socket { 
    return $socket if $socket;
    my $server = 'miltonkeynes.pm';
    $socket = IO::Socket::INET->new(
        PeerHost => $server,
        PeerPort => '7777',
        Proto => 'tcp',
    );
    die "cannot connect to the server $!\n" unless $socket;
} 

sub find_lib { 
    my @args = @_;
    shift @args;
    my $Module = shift @args;
    $Module =~ s!/!::!g;
    $Module =~ s!\.pm!!;
    return if $seen->{$Module};
    my $fhseen = FileHandle->new("> $seenfile") or die("Can't create $seenfile: $!");
    $fhseen->print(Data::Dumper->Dump([$seen], [qw/$seen/]));
    $fhseen->close;
    
    my %config = %hash;
    return if ref $Module eq "CODE";
    $config{Module} = $Module;
    send_data(\%config);
    my $data = get_data();
    foreach my $mod (keys %{ $data->{modules} }) {
        $seen->{$mod} = 1;
    }
        
    $config->{digest_hex} = $data->{digest_hex};
    mkdir $topdir unless -d $topdir;
    if ($data->{modlist}) {
        $modlist = { %{ $data->{modlist} } };
        my $fhlist = FileHandle->new("> $modlistfile") or die("Can't create $modlistfile: $!");
        $fhlist->print(Data::Dumper->Dump([$modlist], [qw/$modlist/]));
        $fhlist->close;
    }
    while (my ($file, $contents) = each %{ $data->{files} }) {
        if ( $Config{archname} =~ m/MSwin/i ) {
            next if $file =~ m/^man/;
        }
        my @dirs = split("/", $file);
        my $filename = pop(@dirs);
        my $d = $topdir;
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
    get_socket() unless $socket;
    # data to send to a server
    my $req = Data::Dumper->Dump([$hash], [qw/$data/]);
    my $size;
    eval {
        $size = $socket->send($req);
    };
    shutdown($socket, 1);

}
sub get_data {
    my $serialized = "";
    my $data;
    do {
        $socket->recv($data, 10000);
        $serialized .= $data;
    }
    until (length $data < 1 );
    eval $serialized;
    return $data;
}
1;
