package RemoteLib;
use Dancer2;
use Module::CoreList;
use Dancer2::Serializer::JSON;
use Data::Dumper;
use File::Find::Rule;
our $VERSION = '0.1';
my $pars = '/home/tony/parrepo';

my @pars = File::Find::Rule->file()->in( $pars );
my %parlibs = ();
foreach my $path (@pars) {
    my $orig_path = $path;
    next unless $path =~ m/\.par$/;
    $path =~ s!^$pars/!!;
    my ($arch, $perlversion, $par) = split('/', $path);
    my @bits = split('-', $par);
    my @module = ();
    foreach my $bit (@bits) {
        last if $bit =~ m/^\d+.\d+$/;
        push(@module, $bit);
    }
    my $modulename = join('::', @module);
    $parlibs{ByArch}{$arch} = $orig_path;
    $parlibs{ByVersion}{$perlversion} = $orig_path;
    $parlibs{ByModule}{$modulename} = $orig_path;
    $parlibs{ByAll}{$arch}{$perlversion}{$modulename} = $orig_path;
}
debug Dumper(\%parlibs);

	

get '/' => sub {
    template 'index';
};
get '/list/:version' => sub {
	my $data = { pars => \%parlibs,
				 corelist => $Module::CoreList::version{param->version} };
	return serialize($data);
	
};
get '/download/:file' =>  sub {
	return send_file(params->{file});
};
get '/upload/:file' =>  sub {
	return send_file(params->{file});
};
true;
