package Test::Cukes::HTTP;

use strict;
use warnings;
use LWP::UserAgent ();
use Test::Cukes;
use Test::More;

our $VERSION = "0.01";

use constant {
    DEFAULT_TIMEOUT       => 60,
    DEFAULT_MAX_REDIRECTS => 5,
    DEFAULT_USER_AGENT    => "Test::Cukes::HTTP/0.01",
};

our $stash = {
    agent => undef,
    url => undef,
};

sub get_useragent {
    my $ua = $stash->{agent} ||= LWP::UserAgent->new(
        agent => DEFAULT_USER_AGENT,
        max_redirect => DEFAULT_MAX_REDIRECTS,
        timeout => DEFAULT_TIMEOUT,
    );
    return $ua;
}

sub do_request {
    my ($url) = @_;
    $stash->{url} = $url;
    my $ua = get_useragent();
    my $req = HTTP::Request->new("GET" => $url);
    if (my $headers = $stash->{request}->{headers}) {
        $req->header($_ => $headers->{$_}) for keys %{$headers};
    }
    delete $stash->{request}; # Cleanup for next request
    my $res = $ua->request($req);
    return ($stash->{res} = $res);
}

sub check_cached {
    my ($stash, $should_be_cached) = @_;

    # Re-request the original URL, it might have been expired
    my $url = $stash->{url};
    my $res = do_request($url);
    if (! $res) {
        return fail("No response object. Maybe you need a 'Given I go to \"<url>\"' first?");
    }

    my $h = $res->headers;
    my $x_varnish = $h->header('X-Varnish');
    my $age = $h->header('Age');
    if ($should_be_cached) {
        like($x_varnish, qr{^ (\d+) \s+ (\d+) $}x,
            "  X-Varnish header contains both current and original XID ($x_varnish)"
        );
        ok(int($age) > 0,
            "  Age of the cached resource is $age"
        );
    }
    else {
        like($x_varnish, qr{^ (\d+) $}x,
            "  X-Varnish header contains only current XID ($x_varnish)"
        );
        is(int($age) => 0,
            "  Age of cached resource is zero"
        );
    }
}

sub check_status_code {
    my ($stash, $expected) = @_;
    my $res = $stash->{res};
    if (! $res) {
        return fail("No response object. Maybe you need a 'Given I go to \"<url>\"' first?");
    }
    my $status = $res->status_line;
    if (ref $expected eq "Regexp") {
        like($status => $expected,
            "  Status line ($status) matches expected line ($expected)"
        );
    }
    else {
        my ($status) = $res->status_line =~ m{^(\d+)};
        is($status => $expected,
            "  Status code is $status (expected $expected)"
        );
    }
}

sub page_content_contains {
    my ($stash, $needle) = @_;

    my $res = $stash->{res};
    if (! $res) {
        return fail("No response object. Maybe you need a 'Given I go to \"<url>\"' first?");
    }

    my $body = $res->content;

    if (index($body, $needle) > -1) {
        return 1;
    }

    return;
}

sub check_redirects_chain_for {
    my ($stash, $expected_url) = @_;
    my $res = $stash->{res};
    if (! $res) {
        return fail("No response object. Maybe you need a 'Given I go to \"<url>\"' first?");
    }
    my @redir = $res->redirects;
    if (! @redir) {
        ok(0);
    }
    else {
        my $found_redir = 0;
        for (@redir) {
            next unless $_;
            my $uri = $_->header("Location");
            #diag("Redirect chain: $uri");
            if ($uri eq $expected_url) {
                $found_redir = 1;
                last;
            }
        }
        ok($found_redir,
            "  Redirect to \"$expected_url\" was " . ($found_redir?'':'not ') . 'found'
        );
    }
    return;
}

Given qr{(?:i will follow) a max of (\d+) redirects}, sub {
    my $ua = get_useragent();
    $ua->max_redirect($1);
    #diag("Set max redirects to '$1'");
};

Given qr{a timeout of (\d+) seconds}, sub {
    my $ua = get_useragent();
    $ua->timeout($1);
    #diag("Set timeout to '$1'");
};

Given qr{a "(.+)" user agent}, sub {
    my ($new_user_agent) = @_;
    my $ua = get_useragent();
    $ua->agent($new_user_agent);
    #diag("Set user agent to '$new_user_agent'");
};

# Given the HTTP request header "Accept" is "text/html"
Given qr{the HTTP request header "(.+)" is "(.*)"}, sub {
    $stash->{request}->{headers}->{$1} = $2;
};

When qr{I go to "(.+)"}, sub {
    my $url = $1;
    $stash->{url} = $url;
    do_request($url);
};

Then qr{the page should be cached}, sub {
    check_cached($stash, 1);
};

Then qr{the page should not be cached}, sub {
    check_cached($stash, 0);
};

Then qr{I should be redirected to "(.+)"}, sub {
    my $url = $1;
    #diag("Matching redirect chain for '$url'");
    return check_redirects_chain_for($stash, $url);
};

Then qr{the (?:final )HTTP status code should be "(.+)"}, sub {
    my $http_status = $1;
    return check_status_code($stash, $http_status);
};

Then qr{the HTTP status line should match "(.+)"}, sub {
    my $http_status = quotemeta($1);
    my $http_status_re = qr{$http_status};
    return check_status_code($stash, $http_status_re);
};

# Then the page does not contain "We are sorry"
Then qr{the page shouldn't contain "(.+)"}, sub {
    my $unwanted_string = $1;
    my $found = page_content_contains($stash, $unwanted_string);
    ok(!$found, "String '$unwanted_string' was not found in the page")
        or diag("Page content: ".$stash->{res}->content);
};

# Then the page contains "We are sorry"
Then qr{the page should contain "(.+)"}, sub {
    my $wanted_string = $1;
    my $found = page_content_contains($stash, $wanted_string);
    ok($found, "String '$wanted_string' was found in the page")
        or diag("Page content: ".$stash->{res}->content);
};

1;