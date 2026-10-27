#!/usr/bin/env perl
use strict;
use warnings;
use IO::Socket::UNIX;
use Socket qw(SOCK_STREAM);

my $leader = shift @ARGV or die "usage: $0 <leader.pl>\n";
my $dir = `mktemp -d`;
chomp $dir;
chmod 0700, $dir;
my $sockpath = "$dir/s.sock";
my $srv = IO::Socket::UNIX->new(
  Local => $sockpath,
  Type => SOCK_STREAM,
  Listen => 1,
) or die $!;
my $pid = fork();
die "fork: $!" unless defined $pid;
if ($pid == 0) {
  exec $^X, $leader,
    '--protocol', '1',
    '--mode', 'owned',
    '--marker', 'bt',
    '--control', $sockpath,
    '--', 'sleep', '3600';
  exit 127;
}
my $cli = $srv->accept() or die $!;
chomp(my $auth = <$cli>);
die "auth" unless $auth eq 'bt';
chomp(my $started = <$cli>);
die "started" unless $started eq 'started';
syswrite($cli, "term\nkill\n");
my $out = '';
while (sysread($cli, my $buf, 4096)) { $out .= $buf; }
waitpid($pid, 0);
system("rm", "-rf", $dir);
print $out;
exit($out =~ /term-forwarded\n/ && $out =~ /killed-group\n/ ? 0 : 1);
