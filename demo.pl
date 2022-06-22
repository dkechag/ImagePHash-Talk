#!/usr/bin/env perl

use strict;
use warnings;
use v5.20;
use feature qw(signatures);
no warnings qw(experimental::signatures portable);
use lib 'lib';
use File::Basename;
use Image::Imlib2;
use Image::PHash;
use Math::DCT ':all';

say "M31 4x4 greyscale data and dct2d";
my $image = Image::Imlib2->load('M31.jpg');
$image = $image->create_scaled_image(4, 4);
my $data = greyscale($image);
say ("[ ".join(', ', map {int($_+0.5)} @$data)." ]");
my $dct2d = dct2d($data);
say ("[ ".join(', ', map {sprintf("%.2f",$_)} @$dct2d)." ]");


my $file = $ARGV[0] || 'b.png';
die "Cannot find $file" unless -f $file;
my $out = fileparse($file, qr/\.\w+$/).".png";
if ($file ne $out) {
    say "Saving as $out";
    my $image = Image::Imlib2->load($file);
    $image->save($out);
    $file = $out;
}

my $res = $ARGV[1] || 256;
die "Res at least 8" unless $res >= 8;

$image = Image::Imlib2->load($file);
$image = $image->create_scaled_image($res, $res);
$image->save("resize_${res}_$file");
$data = greyscale($image);
$image->save("grey_${res}_$file");
$dct2d = dct2d($data);
say "Full $res x $res DCT/iDCT";
dct_images($dct2d);
say "Reduced DCT/iDCT 128x128, 32x32, 16x16";
reduce_draw($data, $_) for qw/128 32 16/;
say "Diagonal DCT/iDCT 45x45/2, 23x23/2";
reduce_draw($data, 45, 'd');
reduce_draw($data, 23, 'd');

say "Swap x<->y (rotate)";
my $newdct = [];
for (my $x = 0; $x < $res; $x++) {
    for (my $y = 0; $y < $res; $y++) {
        push @$newdct, $dct2d->[$res*$y+$x];
    }
}
dct_images($newdct, 'dct_rot_');

say "Mirror";
my $t = 1;
my @new = map { ($t^=1) ? -$_ : $_ } @$dct2d;
dct_images(\@new, 'dct_mirr_');

say "Inverted & mirrored";
$t = 0;
@new = map { ($t^=1) ? -$_ : $_ } @$dct2d;
$new[0] *= -1; # Not the first!
dct_images(\@new, 'dct_invmirr_');

say "Inverted";
@new = map {-$_} @$dct2d;
$new[0] *= -1; # Not the first!
dct_images(\@new, 'dct_inv_');

say "Darken";
my @dark = @$dct2d;
$dark[0] *= 0.5;
dct_images(\@dark, 'dct_dark_');

say "Lighten";
my @light = @$dct2d;
$light[0] *= 1.25;
dct_images(\@light, 'dct_light_');

say "Keep only low frequency";
for (my $y = 0; $y < $res; $y++) {
    for (my $x = 0; $x < $res; $x++) {
        $dct2d->[$res*$y+$x] = 0
            if $x < 128 && $y < 128 && $x + $y > 0;
    }
}
dct_images($dct2d, 'dct_low_');

say "Blur";
$data = load_data("b_blur.png");
$dct2d = dct2d($data);
dct_images($dct2d);

say "1D data";
$data = load_data("upc.png");
$dct2d = dct2d($data);
dct_images($dct2d);

say "White noise";
($file, $data) = white_noise_image($res);
$dct2d = dct2d($data);
dct_images($dct2d);


say "M31 photo phash";
my $h = Image::PHash->new('M31.jpg');
my $img = $h->reducedimage();
$img->save('M31_reduced.png');
$data = greyscale($img);
say "Grayscale ".join(', ', @$data[0..7]);
$img->save('M31_gray.png');
$dct2d = dct2d($data);
say "DCT ".join(', ', map {sprintf('%.2f', $_)} @$dct2d[0..7]);
say $h->pHash(method=>'median');
my $m31 = $h->pHash(method=>'median');
say "phash: $m31";
$m31 = $h->pHash();
say "phash (avg): $m31";

say "Add credit to photo";
compare_phash('M31_s.jpg', 'M31.jpg');
compare_phash('M31_s.jpg', 'M31.jpg', 6);
compare_phash('M31_s.jpg', 'M31.jpg', 7);

say "Do a little crop and contrast";
compare_phash('M31_sc.jpg', 'M31.jpg');
compare_phash('M31_sc.jpg', 'M31.jpg', 6);
compare_phash('M31_sc.jpg', 'M31.jpg', 7);

say "NASA UV M31";
compare_phash('M31_UV.jpg', 'M31.jpg');
compare_phash('M31_UV.jpg', 'M31.jpg', 6);
compare_phash('M31_UV.jpg', 'M31.jpg', 7);

say "Borat";
compare_phash('b.png', 'M31.jpg');

sub compare_phash($image, $ref, $type='') {
    my $iph  = Image::PHash->new($image);
    my $iph2 = Image::PHash->new($ref);
    my $h1 = $iph->pHash(method=>'median');
    my $h2 = $iph2->pHash(method=>'median');
    $h1 = $iph->pHash6() if $type eq '6';
    $h2 = $iph2->pHash6() if $type eq '6';
    $h1 = $iph->pHash7() if $type eq '7';
    $h2 = $iph2->pHash7() if $type eq '7';
    my $diff = diff($h1, $h2);
    say "phash$type: $h1\tdiff: $diff";
}

sub diff($h1, $h2) {
    my $d = (sprintf("%064b", hex($h1)) ^ sprintf("%064b", hex($h2))) =~ tr/\0//c;
    return $d;
}

sub load_data {
    $file = shift;
    my $image = Image::Imlib2->load($file);
    return greyscale($image);
}

sub reduce_draw ($data, $red, $diag = '') {
    my $dct2d = dct2d($data);
    reduce($dct2d, $red, $diag);
    dct_images($dct2d, "dct_$red${diag}_");
}

sub reduce ($data, $red, $diag) {
    my $sz = sqrt(scalar @$data);
    for (my $y = 0; $y < $sz; $y++) {
        for (my $x = 0; $x < $sz; $x++) {
            $data->[$sz*$y+$x] = 0
                if $x >= $red || $y >= $red || ($diag && $y+$x >= $red)
        }
    }
}

sub dct_images ($data, $prefix='dct_') {
    draw_dct_image($data, $prefix);
    draw_dct_image($data, $prefix.'log_', 1);
    my $idct = idct2d($data);
    draw_image($idct, "i$prefix");
}

sub draw_dct_image ($data, $prefix, $log=undef) {
    my $sz  = sqrt(scalar @$data);
    my $max = 1;
    my $exp = $log ? 1 / (1 + ($res**(1 / 3))) : 1;
    $max = abs($data->[$_]) ** $exp > $max ? abs($data->[$_]) ** $exp : $max for 3..$#$data;
    my $img = Image::Imlib2->new($sz, $sz);
    for (my $y = 0; $y < $sz; $y++) {
        for (my $x = 0; $x < $sz; $x++) {
            my $color = $data->[$sz*$y+$x];
            my $c  = int(((abs($color) ** $exp)*255/$max)+0.5);
            $c = 255 if $c > 255;
            $img->set_colour($color > 0 ? 0 : $c, 0, $color < 0 ? 0 : $c, 255);
            $img->draw_point($x, $y);
        }
    }
    say "-> $prefix$file";
    $img->save("$prefix$file");
}

sub draw_image ($data, $prefix = '') {
    my $sz  = sqrt(scalar @$data);
    my $img = Image::Imlib2->new($sz, $sz);
    for (my $y = 0; $y < $sz; $y++) {
        for (my $x = 0; $x < $sz; $x++) {
            my $color = int($data->[$sz*$y+$x]+0.5);
            $color = 255 if $color > 255;
            $color = 0 if $color < 0;
            $img->set_colour($color, $color, $color, 255);
            $img->draw_point($x, $y);
        }
    }
    $img->save("$prefix$file");
}

sub greyscale ($img) {
    my @data;
    for (my $y = 0; $y < $img->height; $y++) {
        for (my $x = 0; $x < $img->width; $x++) {
            my($r, $g, $b, $a) = $img->query_pixel($x,$y);
            my $grey = int($r * 0.3 + $g * 0.59 + $b * 0.11 + 0.5);
            $img->set_colour($grey, $grey, $grey, 255);
            $img->draw_point($x, $y);
            push @data, $grey;
        }
    }
    return \@data;
}

sub white_noise_image ($res) {
    my $img = Image::Imlib2->new($res, $res);
    my @data;
    for (my $y = 0; $y < $img->height; $y++) {
        for (my $x = 0; $x < $img->width; $x++) {
            my($r, $g, $b, $a) = $img->query_pixel($x,$y);
            my $grey = int(rand(256));
            $img->set_colour($grey, $grey, $grey, 255);
            $img->draw_point($x, $y);
            push @data, $grey;
        }
    }
    my $file = "white_noise_$res.png";
    $img->save($file);
    return $file, \@data;
}

# Takes 2D-arrayref. Extremely slow for large sizes at O(n^4)
sub naive_perl_dct2d {
    my $vect = shift;
    my $N    = scalar(@$vect);
    my $fact = 3.1415926535898 / $N;
    my $result;

    for (my $y = 0; $y < $N; $y++) {
        for (my $x = 0; $x < $N; $x++) {
            for (my $i = 0; $i < $N; $i++) {
                my $sum = 0;
                for (my $j = 0; $j < $N; $j++) {
                    $sum += $vect->[$j]->[$i] *
                        cos(($j + 0.5) * $x * $fact) *
                        cos(($i + 0.5) * $y * $fact);
                }
                $result->[$x]->[$y] += $sum;
            }
        }
    }
    return $result;
}