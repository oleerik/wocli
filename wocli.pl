#!/usr/bin/perl

use strict;
use warnings;
use LWP::UserAgent;
use Data::Dumper;
use Getopt::Long;
use File::Path qw(make_path remove_tree);
use IO::Uncompress::Bunzip2 qw(bunzip2 $Bunzip2Error) ;
use XML::Simple qw(:strict);
use DBI;

# Setting autoflush to immediate flush.
$|++;

# Got the DB URL!!!
# It's at: http://clientupdate.curse.com/feed/Complete.xml.bz2
# Global variables
my %config = (
	db => "$ENV{HOME}/.wocli/cache/wocli_db.csv",
	wow_dir => "",
	config_dir => "$ENV{HOME}/.wocli",
	config_file => "config",
	url_base => 'http://www.curse.com',
	uri_home => '/addons/wow?page=1',
	uri_category => '/addons/wow/category',
	uri_complete_db => 'http://clientupdate.curse.com/feed/Complete.xml.bz2'
);
my $DEBUG=0;
my $total_page=1;
my $db = "wocli_db.csv";
my $addon_list_content="";
my %addon_table = ();
my %base_urls = (
	base => 'http://www.curse.com',
	home => 'http://www.curse.com/addons/wow?page=1',
	category => 'http://www.curse.com/addons/wow/category',
);
my $ua;
my $dbi;

# Options
my $opt_build_cache=0;
my $opt_wow_dir = "";
my $opt_extended_cache=0; # If set to 0 build quick cache, if set to 1 build full description cache.
my $opt_write_config=0;
# These 2 options are used for sub-process detailled cache building
my $opt_update_cache_page=0;
my $opt_unzip='/usr/bin/unzip';
my $opt_update_cache_standalone=0;
my $opt_update_cache_max_processes=0; # not used right now
my $opt_no_integrity_check=0; # This option prevent integrity checks (like trying to install an addon that isn't existing).

# Methods

# Print debug messages when debug is enabled
sub debug_print {
	return unless $DEBUG;
	print "[debug] ",@_;
}

sub saveConfig {
	debug_print "Saving config file.\n";
	writeFile("$config{config_dir}/$config{config_file}","# This file was auto-generated by wocli.\nwow_dir=$opt_wow_dir\ndb=$config{db}\nurl_base=$config{url_base}\nuri_home=$config{uri_home}\nuri_category=$config{uri_category}\n");
}

sub loadConfig {
	open(my $fh,"<","$config{config_dir}/$config{config_file}") or die "Can't open $config{config_dir}/$config{config_file} for reading\n";
	while(my $line = <$fh>){
		chomp($line);
		next if($line =~ /^\s*#/);
		if($line =~ /^\s*([^=]+)\s*=\s*(.+)\s*$/){
			debug_print "config defines '$1' with value '$2'\n";
			$config{$1}=$2;
		}
		else{
			print "[warning] '$line' is neither a comment nor a valid config line !\n";
		}
	}
	close($fh);
}

sub unzip {
	my ($file, $dest) = @_;
	debug_print "2>&1 $opt_unzip '$file' -d '$dest' >> $config{config_dir}/unzip.log\n";
	my $status = system("2>&1 $opt_unzip -o '$file' -d $dest >> '$config{config_dir}/unzip.log'");
	if($status == 0){
		return (1, "$file unzipped successfully.");
	}
	elsif ($? == -1) {
		return (0,"failed to execute: $!");
	}
	elsif ($? & 127) {
		return (0,"child died with signal %d, %s coredump"), ($? & 127),  ($? & 128) ? 'with' : 'without';
	}
	else {
		return (0,"child exited with value %d"), $? >> 8;
	}

}

sub installAddon {
	my $addon_shortname = shift(@_);
	if($opt_no_integrity_check || ($addon_table{$addon_shortname})){
		my $response = $ua->get("$base_urls{base}/addons/wow/$addon_shortname/download");
		if ($response->is_success) {
			if($response->decoded_content =~ /<a data-project="(\d+)" data-file="(\d+)" data-href="([^"]+)" class="download-link" href="#">click here<\/a>/){
				my $url = $3;
				if($url=~ /^.*\/([^\/]+)$/){
					my $file = $1;
					debug_print "\t[debug] got addon download URL: $url (dl to $config{config_dir}/cache/$file)\n";
					# TODO: Handle errors like said here: http://search.cpan.org/~riche/File-Path-2.11/lib/File/Path.pm#ERROR_HANDLING
					make_path("$config{config_dir}/cache") unless(-e "$config{config_dir}/cache");
					$response = $ua->get($url,':content_file'=>"$config{config_dir}/cache/$file");
					my ($status,$msg) = unzip("$config{config_dir}/cache/$file","$opt_wow_dir/Interface/AddOns/");
					if($status){
						debug_print "installAddon returning status: ok\n";
						return (1, "install complete.");
					}
					else{
						debug_print "installAddon returning status: NOT ok ($msg)\n";
						return (0, "installation failed due to unzip issue: $msg.");
					}
				}
				else{
					return(0,"Can't extract file name from URL: $url");
				}
			}
			else{
				return(0, "Couldn't extract download URL.");
			}
		}
		else{
			return(0,$response->status_line);
		}
	}
	else{
		return(0,"$addon_shortname is not a valid (existing) addon short name.");
	}
}

sub writeFile{
	my $file_name = shift(@_);
	open(my $fh,">:encoding(UTF-8)",$file_name) or die "Can't open $file_name for writing\n";
	print $fh join('',@_);
	close($fh);
}

sub writeCache{
	my $db_file = shift(@_);
	$db_file = $config{db} unless(defined($db_file));
	debug_print "writeCache: write in $db_file\n";
	open(my $fh,">:encoding(UTF-8)",$db_file) or die "Can't open $db_file for writing\n";
	foreach my $addon_shortname (keys(%addon_table)){
		print $fh "$addon_shortname;$addon_table{$addon_shortname}->{Id};$addon_table{$addon_shortname}->{Name};$addon_table{$addon_shortname}->{DownloadUrl};$addon_table{$addon_shortname}->{Version};$addon_table{$addon_shortname}->{Summary}\n";
	}
	close($fh);
}

sub loadCache {
	open(my $fh,"<",$config{db}) or die "Can't open $config{db} for reading\n";
	while(my $line = <$fh>){
		chomp($line);
		my @split = split(/;/,$line);
		my $shortname = $split[0];
		if(scalar(@split) == 6 ){
			$addon_table{$shortname} = {Id => $split[1], Name => $split[2], DownloadUrl => $split[3], Version => $split[4], Summary => "$split[5]"};
		}
		else{
			debug_print "Not enought field for: $shortname (".scalar(@split)."/6)\n";
			$addon_table{$shortname} = {Id => -1, Name => "$shortname", DownloadUrl => "", Version => "0.0.0", Summary => ""};
		}
	}
	close($fh);
}

sub loadToc{
	my $toc_file = shift(@_);
	debug_print "Loading TOC file: $toc_file\n";
	my %toc_table=(shortname=>"",deps=>[],optdeps=>[],version=>"0.0.0",ischild=>0);
# 	opendir(my $dh, $opt_wow_dir) or die "Can't open directory $opt_wow_dir for reading\n";
# 	my @tocs = grep { /^.*\.toc$/i } readdir($dh);
# 	closedir $dh;
	open my $fh, "<","$toc_file" or die "Can't open $toc_file for reading\n";
	## Dependencies: AtlasLoot_Loader
	## LoadOnDemand: 1
	## OptionalDeps: Ace3, LibBabble-Boss-3.0, LibBabble-Faction-3.0, LibBabble-Inventory-3.0, LibBabble-ItemSet-3.0, LibBabble-Zone-3.0, LibDBIcon-1.0, LibDataBroker-1.1
	## X-Curse-Packaged-Version: v6.05.03
	## X-Curse-Project-Name: AtlasLoot Enhanced
	## X-Curse-Project-ID: atlasloot-enhanced
	while(my $line = <$fh>){
		chomp($line);
# 		debug_print "(loadToc): '$line'\n";
# 		my $shortname = "";
# 		my $name = "";
# 		my $version = "0.0.0";https://stormboard.com/
# 		my $updateversion = "0.0.0";
		
		if($line=~/^\s*##\s*X-Curse-Project-ID:\s*([^\s]+)/i){
			$toc_table{shortname}=$1;
			debug_print "(loadToc): found X-Curse-Project-ID => '$toc_table{shortname}'\n";
		}
		elsif( $line=~/^\s*##\s*X-Curse-Packaged-Version:\s*([^\s]+)/i ){
			$toc_table{version}=$1;
		}
		elsif( $line=~/^\s*##\s*Dependencies:\s*([^\s]+)/i ){
			$toc_table{deps}=[split(/,\s*/,$1)];
		}
		elsif( $line=~/^\s*##\s*OptionalDeps:\s*([^\s]+)/i ){
			$toc_table{optdeps}=[split(/,\s*/,$1)];
		}
		elsif($line=~/^\s*##\s*X-Child-Of:\s*([^\s]+)/i){
			debug_print "(loadToc): $toc_file is a child of $1\n";
			$toc_table{ischild}=1;
		}
		
	}
	
	close $fh;
	return(%toc_table);
}

sub updateCache {
	make_path("$config{config_dir}/cache/tmp/") unless( -d "$config{config_dir}/cache/tmp/");
	# TODO: turn that to actual proper code...
	debug_print "Downloading new cache\n";
	print "Downloading cache...";
	system("rm -rf $config{config_dir}/cache/tmp/*");
	my $response = $ua->get($config{uri_complete_db},':content_file'=>"$config{config_dir}/cache/tmp/Complete.xml.bz2");

	if($response->is_success){
		print "ok\n";
		debug_print "Unziping database\n";
		print "Unzipping database...";
		my $status = bunzip2 "$config{config_dir}/cache/tmp/Complete.xml.bz2" => "$config{config_dir}/cache/tmp/Complete.xml" or die "bunzip2 failed: $Bunzip2Error\n";
		print "ok\n";
		# TODO: Parse the XML...
		my $complete = XMLin("$config{config_dir}/cache/tmp/Complete.xml", KeyAttr => {}, ForceArray => [ 'CAddOnCategory', 'Dependencies', 'CAddOnFileDependency', 'Modules', 'CAddOnModule', 'a:string', 'CAddOnAuthor', 'CAddOnFile' ]);
		my $wac = 0;
		my $tac = 0;
		foreach my $caddon (@{$complete->{'CAddOn'}}){
			if($caddon->{'CategorySection'}->{'GameID'} == 1){
				$wac++;
				$caddon->{'Summary'} =~ s/;/,/g;
				my @url = split(/\//,$caddon->{'WebSiteURL'});
				$addon_table{$url[$#url]} = { Id => $caddon->{'Id'}, Name => $caddon->{'Name'}, DownloadUrl => $caddon->{'LatestFiles'}->{'CAddOnFile'}->[0]->{'DownloadURL'}, Version => $caddon->{'LatestFiles'}->{'CAddOnFile'}->[0]->{'FileName'}, Summary => "$caddon->{'Summary'}" };
			}
			$tac++;
		}
		debug_print Data::Dumper::Dumper(%addon_table),"\n";
		debug_print "WoW addons found (WoW/Total): $wac/$tac\n";
		print "Cache updated with $wac addons.\n";
		writeCache();
	}
	else{
		print "not ok.\n";
		die "Error while downloading Curse.com database: ".$response->status_line."\n";
	}
	
}



# Getting options from command line.
GetOptions(
  "build-cache"=>\$opt_build_cache,
  "extended"=>\$opt_extended_cache,
  "update-cache-page=i"=>\$opt_update_cache_page,
  "update-cache-standalone"=>\$opt_update_cache_standalone,
  "wow-dir=s" => \$opt_wow_dir,
  "save" => \$opt_write_config,
  "no-integrity-check" => \$opt_no_integrity_check,
  "debug" => \$DEBUG
);

# Loading configuration 
if( -e "$config{'config_dir'}/$config{'config_file'}" ){
	debug_print "Loading config from $config{'config_dir'}/$config{'config_file'}\n";
	loadConfig();
	$opt_wow_dir = $config{wow_dir} if($opt_wow_dir eq "");
}
else{
	debug_print "File $config{'config_dir'}/$config{'config_file'} does not exists, going on with default values.\n";
}


debug_print "/!\\ DEBUG is enabled, it can generate a lot of output/!\\\n";
debug_print "WoW directory: $opt_wow_dir\n";
debug_print "Remaining args: ".join(',',@ARGV)."\n";
debug_print "DB: $config{db}\n";

mkdir $config{'config_dir'} unless (-e $config{'config_dir'});
mkdir "$config{'config_dir'}/cache" unless (-e "$config{'config_dir'}/cache");

saveConfig() if($opt_write_config);

$ua = LWP::UserAgent->new(agent => 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/40.0.2214.94 Safari/537.36');
$ua->timeout(10);
$ua->env_proxy;

if( -e $config{db} && !$opt_build_cache ){
	debug_print "Loading cache (no download)\n";
	loadCache();
}
else{
	debug_print "Downloading new cache\n";
	updateCache();
}

die "command required: install, update, remove, search, clean, builddb, buildcache.\n" unless(defined($ARGV[0]));

my $cmd = shift(@ARGV);
debug_print "Self is: $^X $0\n";
debug_print "COMMAND: $cmd\n";

if($cmd eq 'install') {
	foreach my $addonToInstall (@ARGV){
		print "Install:\t$addonToInstall\t\t\t\t:\t";
		# TODO install Dependencies!
		my ($status,$msg) = installAddon($addonToInstall);
		if($status){
			print "installed.\n";
		}
		else{
			print "installation failed ($msg).\n";
		}
	}
	
}
elsif($cmd eq 'update'){
	# Now we get to look for installed addons. There is a thing with update (see Titan pannel).
	my @toc_files = split(/\n/,`find '$opt_wow_dir' -name "*.toc"`);
	my @update_list = ();
	foreach my $tf (@toc_files){
		my %toc_data = loadToc($tf);
		if(defined($toc_data{'shortname'}) &&  exists($addon_table{$toc_data{'shortname'}})){
			debug_print "UPDATE: $toc_data{'shortname'} IS AN ADDON FOUND IN THE DATABASE.\n";
			push(@update_list, $toc_data{'shortname'});
		}
		else {
			debug_print "update: $toc_data{'shortname'} is not a root addon provided by curse.\n";
		}
	}
	print "Following addons are going to be updated:\n",join(', ',@update_list),"\n";
	foreach my $addonToUpdate (@update_list){
		print "Update:\t$addonToUpdate\t\t\t\t:\t";
		my ($status,$msg) = installAddon($addonToUpdate);
		if($status){
			print "updated.\n";
		}
		else{
			print "update failed ($msg).\n";
		}
	}
}
elsif($cmd eq 'clean'){
	remove_tree("$config{config_dir}/cache",{error => \my $err});
	if (@$err) {
	for my $diag (@$err) {
		my ($file, $message) = %$diag;
		if ($file eq '') {
			print "general error: $message\n";
		}
		else {
			print "problem unlinking $file: $message\n";
		}
	}
	}
	else {
		print "Cache cleaned\n";
	}
}
elsif($cmd eq 'buildcache'){
	debug_print "Building new cache\n";
	updateCache();
}
else{
	die "Unknown command: $cmd\n";
}

exit(0);