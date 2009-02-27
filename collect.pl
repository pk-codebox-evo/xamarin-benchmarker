#!/usr/bin/perl

use strict;
use Cairo;
use List::Util qw(min max);

sub make_revisions_path {
    my ($cr, $revisions, $data, $key, $moveto) = @_;
    my @revisions = @$revisions;
    my %data = %$data;

    if ($moveto) {
	$cr->move_to($revisions[0], $data{$revisions[0]}{$key});
	@revisions = @revisions[1 .. $#revisions];
    }

    foreach my $revision (@revisions) {
	$cr->line_to($revision, $data{$revision}{$key});
    }
}

sub transform_coords {
    my ($cr, $img_width, $img_height, $min_x, $max_x, $min_y, $max_y) = @_;

    $cr->scale($img_width / ($max_x - $min_x), - $img_height / ($max_y - $min_y));
    $cr->translate(0, - ($max_y - $min_y));
    $cr->translate(-$min_x, -$min_y);
}

sub plot_cairo_combined {
    my ($combined_data, $filename, $img_width, $img_height, $line_width) = @_;
    my %combined_data = %$combined_data;

    my $surface = Cairo::ImageSurface->create('rgb24', $img_width, $img_height);
    my $cr = Cairo::Context->create($surface);

    $cr->set_source_rgb(1, 1, 1);
    $cr->rectangle(0, 0, $img_width, $img_height);
    $cr->fill;

    my @revisions = sort { $a <=> $b } keys %combined_data;

    my $min_x = min @revisions;
    my $max_x = max @revisions;
    my $min_y = min (map { $combined_data{$_}{"min"} } @revisions);
    my $max_y = max (map { $combined_data{$_}{"max"} } @revisions);

    #avg
    $cr->save;
    transform_coords($cr, $img_width, $img_height, $min_x, $max_x, $min_y, $max_y);
    make_revisions_path($cr, \@revisions, \%combined_data, "avg", 1);
    $cr->restore;

    $cr->set_line_width($line_width);
    $cr->set_source_rgb(0, 0, 0);
    $cr->stroke;

    #min
    $cr->save;
    transform_coords($cr, $img_width, $img_height, $min_x, $max_x, $min_y, $max_y);
    make_revisions_path($cr, \@revisions, \%combined_data, "min", 1);
    $cr->restore;

    $cr->set_line_width($line_width);
    $cr->set_source_rgb(0, 0.6, 0);
    $cr->stroke;

    #max
    $cr->save;
    transform_coords($cr, $img_width, $img_height, $min_x, $max_x, $min_y, $max_y);
    make_revisions_path($cr, \@revisions, \%combined_data, "max", 1);
    $cr->restore;

    $cr->set_line_width($line_width);
    $cr->set_source_rgb(1, 0, 0);
    $cr->stroke;

    $cr->show_page;

    $surface->write_to_png($filename);
}

opendir DIR, "configs" or die;
my @configs = grep { !/^\.\.?$/ && (-d "configs/$_") } readdir DIR;
closedir DIR;

foreach my $config (@configs) {
    my $basedir = "configs/$config";

    my %test_rev_data = ();
    my %test_data = ();

    my %revisions = ();

    my %inverse_tests = ( "scimark" => 10000 );

    opendir DIR, $basedir or die;
    my @rev_dirs = grep /^r\d+$/, readdir DIR;
    closedir DIR;

    foreach my $subdir (@rev_dirs) {
	$subdir =~ /^r(\d+)$/ or die;
	my $revision = $1;

	my $dir = "$basedir/$subdir";
	opendir DIR, $dir or die;
	my @filenames = grep /\.times$/, readdir DIR;
	closedir DIR;

	foreach my $filename (@filenames) {
	    $filename =~ /^(.+)\.times$/ or die;
	    my $test = $1;
	    my @values;

	    open FILE, "<$dir/$filename" or die;
	    while (<FILE>) {
		chomp;
		$_ =~ /^\d+(\.\d+)?$/ or die;
		push @values, $_;
	    }
	    close FILE;

	    @values > 0 or die;

	    if (exists $inverse_tests{$test}) {
		@values = map { $inverse_tests{$test} / $_ } @values;
	    }

	    my $min = $values[0];
	    my $max = $values[0];
	    my $sum = 0;

	    foreach my $value (@values) {
		$sum += $value;
		$min = $value if $value < $min;
		$max = $value if $value > $max;
	    }

	    my $avg = $sum / @values;

	    $test_rev_data{$test}{$revision}{"min"} = $min;
	    $test_rev_data{$test}{$revision}{"max"} = $max;
	    $test_rev_data{$test}{$revision}{"avg"} = $avg;

	    $revisions{$revision} = 1;

	    open FILE, "<$dir/$test.size" or die;
	    my $size = <FILE> or die;
	    close FILE;

	    chomp $size;
	    $size =~ /^\d+$/ or die "cannot parse size for $dir/$test.size";
	    $test_rev_data{$test}{$revision}{"size"} = $size;
	}
    }

    #compute test data
    foreach my $test (keys %test_rev_data) {
	my $sum = 0;
	my $n = 0;
	my $min_rev = undef;
	my $max_rev = undef;

	foreach my $revision (keys %{$test_rev_data{$test}}) {
	    my $val = $test_rev_data{$test}{$revision}{"avg"};
	    $sum += $val;
	    ++$n;

	    if (defined $min_rev) {
		$min_rev = $revision if $val < $test_rev_data{$test}{$min_rev}{"avg"};
		$max_rev = $revision if $val > $test_rev_data{$test}{$max_rev}{"avg"};
	    } else {
		$min_rev = $revision;
		$max_rev = $revision;
	    }
	}

	my $avg = $sum / $n;

	$test_data{$test}{"avg"} = $avg;
	$test_data{$test}{"avg_min_rev"} = $min_rev;
	$test_data{$test}{"avg_max_rev"} = $max_rev;
    }

    #write plot data for single tests
    foreach my $test (keys %test_rev_data) {
	open FILE, ">$basedir/$test.dat" or die;

	print FILE "#revision size avg min max\n";

	foreach my $revision (sort { $a <=> $b } keys %{$test_rev_data{$test}}) {
	    my $size = $test_rev_data{$test}{$revision}{"size"};
	    my $min = sprintf "%.2f", $test_rev_data{$test}{$revision}{"min"};
	    my $max = sprintf "%.2f", $test_rev_data{$test}{$revision}{"max"};
	    my $avg = sprintf "%.2f", $test_rev_data{$test}{$revision}{"avg"};
	    print FILE "$revision $size $avg $min $max\n";
	}

	close FILE;

	my $avg_min_rev = $test_data{$test}{"avg_min_rev"};
	my $avg_min = $test_rev_data{$test}{$avg_min_rev}{"avg"};

	open FILE, ">$basedir/$test.min.dat" or die;
	print FILE "$avg_min_rev $avg_min\n";
	close FILE;

	my $avg_max_rev = $test_data{$test}{"avg_max_rev"};;
	my $avg_max = $test_rev_data{$test}{$avg_max_rev}{"avg"};

	open FILE, ">$basedir/$test.max.dat" or die;
	print FILE "$avg_max_rev $avg_max\n";
	close FILE;
    }

    #compute combined plot data
    my %combined_data = ();

    foreach my $revision (keys %revisions) {
	my $sum = 0;
	my $n = 0;
	my $min = undef;
	my $max = undef;

	foreach my $test (keys %test_rev_data) {
	    if (exists $test_rev_data{$test}{$revision}) {
		my $value = $test_rev_data{$test}{$revision}{"avg"} / $test_data{$test}{"avg"};

		$sum += $value;
		++$n;

		if (defined($min)) {
		    $min = $value if $value < $min;
		    $max = $value if $value > $max;
		} else {
		    $min = $value;
		    $max = $value;
		}
	    }
	}

	my $avg = $sum / $n;

	$combined_data{$revision}{"avg"} = $avg;
	$combined_data{$revision}{"min"} = $min;
	$combined_data{$revision}{"max"} = $max;
    }

    #combined plot
    plot_cairo_combined(\%combined_data, "$basedir/combined_large.png", 500, 150, 2);
    plot_cairo_combined(\%combined_data, "$basedir/combined.png", 150, 35, 1);

    #write html index
    my @last_revs = (sort { $a <=> $b } keys %revisions) [-3 .. -1];

    open FILE, ">$basedir/index.html" or die;
    print FILE "<html><body><h1>$config</h1>\n";
    print FILE "<p><img src=\"combined_large.png\">\n";
    print FILE "<p><table>\n";

    print FILE "<tr><td>Test</td><td>Best</td><td>Worst</td>";
    foreach my $rev (@last_revs) {
	print FILE "<td>r$rev</td>";
    }
    print FILE "<td>Graph</td></tr>\n";

    foreach my $test (sort keys %test_rev_data) {
	print FILE "<tr><td><a href=\"$test.html\">$test</a></td>";

	my $avg_min_rev = $test_data{$test}{"avg_min_rev"};
	my $avg_min = $test_rev_data{$test}{$avg_min_rev}{"avg"};
	my $avg_max_rev = $test_data{$test}{"avg_max_rev"};
	my $avg_max = $test_rev_data{$test}{$avg_max_rev}{"avg"};

	printf FILE "<td>%.2f (r$avg_min_rev)</td><td>%.2f (r$avg_max_rev)</td>", $avg_min, $avg_max;

	foreach my $rev (@last_revs) {
	    my $val;

	    if (exists $test_rev_data{$test}{$rev}) {
		$val = sprintf "%.2f", $test_rev_data{$test}{$rev}{"avg"};
	    } else {
		$val = "-";
	    }

	    print FILE "<td>$val</td>";
	}

	print FILE "<td><a href=\"$test\_large.png\"><img src=\"$test.png\"></a></td></tr>\n";
    }
    print FILE "</table>\n";
    print FILE "</body></html>";
    close FILE;

    #write html for tests
    foreach my $test (keys %test_rev_data) {
	open FILE, ">$basedir/$test.html" or die;

	print FILE "<html><body><h1>$test on $config</h1>\n";
	print FILE "<p><img src=\"$test\_large.png\">\n";

	print FILE "<p><table><tr><td>Revision</td><td>Average</td><td>Min</td><td>Max</td><td>Size (bytes)</td></tr>\n";
	foreach my $revision (sort { $a <=> $b } keys %{$test_rev_data{$test}}) {
	    my $avg = $test_rev_data{$test}{$revision}{"avg"};
	    my $min = $test_rev_data{$test}{$revision}{"min"};
	    my $max = $test_rev_data{$test}{$revision}{"max"};
	    my $size = $test_rev_data{$test}{$revision}{"size"};

	    printf FILE "<tr><td>r$revision</td><td>%.2f</td><td>%.2f</td><td>%.2f</td><td>$size</td></tr>\n", $avg, $min, $max;
	}
	print FILE "</table>\n";

	print FILE "</body></html>\n";

	close FILE;
    }
}

#write main index
open FILE, ">configs/index.html" or die;

print FILE "<html><body>\n";

print FILE "<table><tr><td>Config</td><td>Graph</td></tr>\n";
foreach my $config (@configs) {
    print FILE "<tr><td><a href=\"$config/index.html\">$config</a></td>";
    print FILE "<td><a href=\"$config/combined_large.png\"><img src=\"$config/combined.png\"></a></td></tr>\n";
}
print FILE "</table>\n";

print FILE "</body></html>\n";

close FILE;
