use strict;
use warnings;
use utf8;

use Irssi;
use Time::HiRes qw(gettimeofday);
use IO::Socket::SSL;
use LWP::UserAgent;

use vars qw($VERSION %IRSSI);

$VERSION = "0.1";
%IRSSI = (
    authors     => "dxsh",
    contact     => 'dxsh@riseup.net',
    name        => "avanza.pl",
    description => "fetch stock prices from avanza.se",
    license     => "MIT",
);

my $url = "https://avanza.se";
my $ua = LWP::UserAgent->new(agent      => "avanza.pl/$VERSION",
                             timeout    => 10,
                             ssl_opts   => {
                                 verify_hostname => 0,
                                 SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE,
                             },
                         );

sub get_stocks {
    my ($stock) = @_;
    my $html;
    my @stock_hashes = ();
    my $search_path = "/ab/sok/inline\?query=$stock&_=" . int(gettimeofday * 1000);
    my $search_result = $ua->get($url . $search_path);

    if ($search_result->is_success) {
        $html = $search_result->content;

        if ($html =~ /du\sfick\singa.+?/i) {
            return "no matches found.";
        }
    }
    else {
        return "error: avanza returned a non-200 http status code";
    }

    my @paths = $html =~ /\/aktier\/.+?(?=["'])/gis;

    foreach my $path (@paths) {
        my $link = $url . $path;
        my $stock_data = get_stock_data($link);
        push @stock_hashes, $stock_data;
    }

    return @stock_hashes;
}

sub get_stock_data {
    my ($url) = @_;
    my $stock_page = $ua->get($url)->content;
    my %stock_data;
    my $stock_name_re = qr/<title>(.*?(?=-))/i;
    my %stock_data_re = (
        change_percentage   => qr/changePercent\sSText.*?">(.+?)</is,
        change_currency     => qr/change\b.*?">(.+?)</is,
        buy                 => qr/buyPrice\sSText.*?">(.+?)</is,
        sell                => qr/sellPrice\sSText.*?">(.+?)</is,
        latest              => qr/pushBox\sroundCorners3.*?">(.+?)</is,
        highest             => qr/highestPrice\sSText.*?">(.+?)</is,
        lowest              => qr/lowestPrice\sSText.*?">(.+?)</is
    );

    # avanza doesn't return a non-200 http status code even if the stock
    # is nonexistent.
    if ($stock_page =~ /sidan\sdu\svill\sse\skan\sinte\svisas/i) {
        return "error: unable to fetch data from $url";
    }

    foreach my $x (keys %stock_data_re) {
        my $stock_name_re = $stock_page =~ $stock_name_re;
        my $stock_name = $1;
        $stock_page =~ $stock_data_re{$x};
        $stock_data{$stock_name}{$x} = $1;
    }

    return \%stock_data;
}

sub msg_stocks {
    my ($server, $msg, $nick, $address, $target) = @_;
    my ($cmd, $l) = split(/ :/, $msg, 2);

    if ($cmd =~ /^\.stock.+/i) {
        my $stock_re = $cmd =~ qr/\.stock\s*(\w*)/i;
        my @stock = get_stocks($1);
        my @stock_data;

        if (ref($stock[0]) ne "HASH") {
            $server->command("MSG $target $stock[0]");
            return;
        }

        foreach my $i (0 .. $#stock) {
            foreach my $x (keys $stock[$i]) {
                my $stock_name = $x;
                push @stock_data, $stock_name;
                foreach my $y (keys $stock[$i]{$x}) {
                    push @stock_data, "$y: $stock[$i]{$x}{$y}";
                }

                $server->command("MSG $target " . join(" | ", @stock_data));
                undef @stock_data;
            }
        }
    }
}

Irssi::signal_add("message public", "msg_stocks");

# vim: set ts=4 sw=4 tw=80 ft=perl et :
