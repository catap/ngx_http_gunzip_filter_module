#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for gunzip filter module.

###############################################################################

use warnings;
use strict;

use Test::More;
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

eval { require IO::Compress::Gzip; };
Test::More::plan(skip_all => "IO::Compress::Gzip not found") if $@;

my $t = Test::Nginx->new()->has('--with-http_gzip_static_module')->plan(10);

$t->write_file_expand('nginx.conf', <<'EOF');

master_process off;
daemon         off;

events {
}

http {
    access_log    off;
    root          %%TESTDIR%%;

    client_body_temp_path  %%TESTDIR%%/client_body_temp;
    fastcgi_temp_path      %%TESTDIR%%/fastcgi_temp;
    proxy_temp_path        %%TESTDIR%%/proxy_temp;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;
        location / {
            gunzip on;
            gzip_vary on;
            proxy_pass http://127.0.0.1:8081/;
            proxy_set_header Accept-Encoding gzip;
        }
        location /error {
            error_page 500 /t1;
            return 500;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            default_type text/plain;
            gzip_static on;
            gzip_http_version 1.0;
            gzip_types text/plain;
        }
    }
}

EOF

my $in = join('', map { sprintf "X%03dXXXXXX", $_ } (0 .. 99));
my $out;

IO::Compress::Gzip::gzip(\$in => \$out);

$t->write_file('t1.gz', $out);
$t->write_file('t2.gz', $out . $out);
$t->write_file('t3', 'not compressed');

$t->run();

###############################################################################

pass('runs');

my $t1 = http_get('/t1');
unlike($t1, qr/Content-Encoding/, 'no content encoding');
like($t1, qr/^(X\d\d\dXXXXXX){100}$/m, 'correct ungzipped response');

like(http_get('/t2'), qr/^(X\d\d\dXXXXXX){200}$/m, 'multiple gzip members');

like(http_get('/error'), qr/^(X\d\d\dXXXXXX){100}$/m, 'errors ungzipped');

unlike(http_head('/t1'), qr/Content-Encoding/, 'head - no content encoding');

like(http_get('/t1'), qr/Vary/, 'get vary');
like(http_head('/t1'), qr/Vary/, 'head vary');
unlike(http_get('/t3'), qr/Vary/, 'no vary on non-gzipped get');
unlike(http_head('/t3'), qr/Vary/, 'no vary on non-gzipped head');

###############################################################################
