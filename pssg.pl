#!/usr/bin/env perl

use 5.012;
use strict;
use warnings;

use Getopt::Std;
use File::Find::Rule;
use File::Path;
use File::Spec;
use Text::Nimble;

my $version         = "0.2";
my $nimble_file_ext = "nb";

sub print_help {
    print "pssg\n";
    print "====\n";
    print "version: $version\n";
    print "options:\n\n";
    print "\t-c\tclean output directory\n";
    print "\t-h\thelp\n";
    print "\t-f\tinput directory\n";
    print "\t-m\tmacro file\n";
    print "\t-o\toutput directory\n";
    print "\t-s\tstyle sheet file\n";
}

sub render_html {
    my $infile  = shift(@_);
    my $outfile = shift(@_);
    my $nav     = shift(@_);
    my $styles  = shift(@_);
    my $macros  = shift(@_);

    my $pre = <<"END";
<!DOCTYPE html>
<html>
<head>
    <style>$styles</style>
</head>
<body>
$nav
END

    my $end = <<"END";
</body>
</html>
END

    print "[REND] Rendering file '$infile'...\n";
    open(my $fh, "<", $infile)
        or die "[ERR ] Can't open '$infile': $!";

    my $text;
    {
        local $/ = undef;
        $text    = <$fh>;
    }
    my $ast = Text::Nimble::parse($macros . $text);
    my ($html, $meta, $errors) = Text::Nimble::render(html => $ast);

    if ($errors) {
        print "[RND ] Errors: '$errors'\n";
    }

    print "[REND] Writing output to '$outfile'...\n";
    open(my $out, ">", $outfile)
        or die "[ERR ] Can't open '$outfile': $!";

    print $out $pre;
    print $out $html;
    print $out $end;
}

sub build_nav_link {
    my $file = shift(@_);
    my $root = shift(@_);
    print "[NAV ] File '$file'\n";
    my $title = build_title($file);
    $file =~ s/$root//;
    $file =~ s/\.$nimble_file_ext$/.html/;
    return "<li><a href=\"$file\">$title</a></li>\n";
}

sub build_nav_dir {
    my $parent = shift(@_);
    my $root   = shift(@_);
    print "[NAV ] Dir  '$parent'\n";

    my $nav = "";
    my $title  = build_title($parent);
    opendir(my $dh, $parent);
    while (readdir $dh) {
        my $file = "$parent/$_";

        next if $_ eq ".";
        next if $_ eq "..";
        if ($_ eq ".title") {
            open(my $fh, "<", $file)
                or die "[ERR ] Can't open '$file': $!";
            $title = <$fh>;
        }
        if (-f $file) {
            next unless $file =~ /\.$nimble_file_ext$/;
            $nav .= build_nav_link($file, $root);
        }
        if (-d $file) {
            $nav .= build_nav_dir($file, $root);
        }
    }
    if ($nav eq "") {
        return "";
    }
    $parent =~ s/.*\///;
    return "<li><p>$title</p><ul>\n$nav</ul></li>\n";
}

sub build_nav {
    my $root = shift(@_);
    print "[NAV ] Building Navigation from root '$root'\n";
    my $elements = build_nav_dir($root, $root);
    return <<"END";
<section>
    <h1>Navigation</h1>
    <nav>
        <ul>$elements</ul>
    </nav>
</section>
END
}

sub build_title {
    my $path = shift(@_);

    if (-f $path) {
        open(my $fh, "<", $path)
            or die"[ERR ] Can't open '$path': $!";
        foreach my $line (<$fh>) {
            if ($line =~ m/^(\{|!1) .*$/) {
                my $title = $line =~ s/^(\{|!1) //r;
                return $title;
            }
        }
    }
    $path =~ s/^.*\///;
    $path =~ s/[-]/ /g;
    return $path;
}

print "[INFO] Starting pssg version $version\n";

# Parse command line arguments
my $reqargs = "f:o:";
my $optargs = "chm:s:";
my %options = ();
getopts("$reqargs$optargs", \%options);

if ($options{h}) {
    print_help();
    exit(0);
}

# Make sure all the required arguments are given
$reqargs =~ s/://g;
foreach my $arg (split(//, $reqargs)) {
    if (!$options{$arg}) {
        print "[ERR ] Required option '$arg' not set!\n";
        exit(1);
    }
}

my $indir  = File::Spec->rel2abs($options{f});
my $outdir = File::Spec->rel2abs($options{o});

# Optional arguments
my $macros;
if ($options{m}) {
    open(my $fh, "<", File::Spec->rel2abs($options{m}))
        or die "[ERR ] Can't open '$options{m}': $!";
    local $/ = undef;
    $macros  = <$fh>;
    $macros .= "\n";
} else {
    $macros = "";
}

my $styles;
if ($options{s}) {
    open(my $fh, "<", File::Spec->rel2abs($options{s}))
        or die "[ERR ] Can't open '$options{s}': $!";
    local $/ = undef;
    $styles  = <$fh>;
    $styles .= "\n";
} else {
    $styles = "";
}

if ($options{c}) {
    print "[INFO] Cleaning directory '$outdir'...\n";
    File::Path->remove_tree($outdir);
}

# Build nav
my $nav = build_nav($indir);

my @infiles = File::Find::Rule->file()
                              ->name("*.$nimble_file_ext")
                              ->in($indir);

# Build pages
foreach my $in (@infiles) {
    my $out = $in =~ s/$indir/$outdir/r;
    $out =~ s/\.$nimble_file_ext$/\.html/;
    my ($drive, $dir, $file) = File::Spec->splitpath($out);

    File::Path->make_path($dir);
    render_html($in, $out, $nav, $styles, $macros);
}

print "[INFO] Finished rendering\n";

