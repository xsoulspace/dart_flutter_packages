#!/usr/bin/env perl
# Protocol p1 owned-session leader (Perl reference implementation).
# Contract: doc/owned_session_p1.md — moves to oka_process without argv/socket changes.

use strict;
use warnings;
use Fcntl qw(F_SETFD FD_CLOEXEC);
use IO::Socket::UNIX;
use POSIX qw(WNOHANG setsid);
use Socket qw(SOCK_STREAM);

sub emit_error {
  my ($marker, $stage, $detail) = @_;
  $marker = '' unless defined $marker;
  print STDERR "$marker:error:$stage:$detail\n";
  exit(1);
}

sub run_graceful_hook {
  my ($sock, $marker, $hook, $timeout_secs) = @_;
  return unless defined $hook && length $hook;
  $timeout_secs = 2 unless defined $timeout_secs && $timeout_secs > 0;
  local $SIG{ALRM} = sub { die "graceful timeout\n" };
  eval {
    local $ENV{BOUNDED_SESSION_MARKER} = $marker;
    alarm $timeout_secs;
    my $rc = system($hook, $marker);
    alarm 0;
    if ($rc == -1) {
      print $sock "graceful:fail:spawn\n";
    } elsif ($rc == 0) {
      print $sock "graceful:ok\n";
    } else {
      print $sock "graceful:fail:$rc\n";
    }
    $sock->flush();
  };
  if ($@) {
    alarm 0;
    eval {
      print $sock "graceful:timeout\n";
      $sock->flush();
    };
  }
}

my %opt;
while (@ARGV && $ARGV[0] =~ /^--/) {
  my $key = shift @ARGV;
  if ($key eq '--protocol') { $opt{protocol} = shift @ARGV; }
  elsif ($key eq '--mode') { $opt{mode} = shift @ARGV; }
  elsif ($key eq '--marker') { $opt{marker} = shift @ARGV; }
  elsif ($key eq '--control') { $opt{control} = shift @ARGV; }
  elsif ($key eq '--graceful') { $opt{graceful} = shift @ARGV; }
  elsif ($key eq '--graceful-timeout') { $opt{graceful_timeout} = shift @ARGV; }
  elsif ($key eq '--') { last; }
  else { shift @ARGV; }
}

my $marker = $opt{marker} || emit_error('', 'args', 'marker');
emit_error($marker, 'protocol', 'version') unless ($opt{protocol} || '') eq '1';
emit_error($marker, 'mode', 'owned') unless ($opt{mode} || '') eq 'owned';
my $ctl_path = $opt{control} || emit_error($marker, 'control', 'path');

select STDERR; $| = 1;
my $sid = POSIX::setsid();
emit_error($marker, 'setsid', $! + 0) if $sid < 0;
print STDERR "$marker:ready:$sid:p1:perl\n";

my $sock = IO::Socket::UNIX->new(Type => SOCK_STREAM, Peer => $ctl_path);
emit_error($marker, 'control', $! + 0) unless $sock;
print $sock "$marker\n";
$sock->flush();

pipe(my $read_error, my $write_error) or emit_error($marker, 'pipe', $! + 0);
my $child = fork();
emit_error($marker, 'fork', $! + 0) unless defined $child;
if ($child == 0) {
  close($read_error);
  fcntl($write_error, F_SETFD, FD_CLOEXEC) or do {
    print $write_error "exec pipe: $!";
    exit(1);
  };
  exec { $ARGV[0] } @ARGV;
  print $write_error "exec: $!";
  close($write_error);
  exit(1);
}
my $main_status = 0;
my $main_reported = 0;
my $exit_sent = 0;
close($write_error);
my $error = '';
while (sysread($read_error, my $buffer, 4096)) { $error .= $buffer; }
close($read_error);
if (length($error)) {
  emit_error($marker, 'exec', $error);
}

print $sock "started\n";
$sock->flush();

sub report_main_exit {
  return if $exit_sent;
  my $reaped = waitpid($child, WNOHANG());
  return unless $reaped > 0;
  $main_status = $?;
  $main_reported = 1;
  print $sock "exit:$main_status\n";
  $sock->flush();
  $exit_sent = 1;
}

report_main_exit();

$SIG{TERM} = 'IGNORE';

sub read_control_line {
  my ($handle, $seconds) = @_;
  my $rin = '';
  vec($rin, fileno($handle), 1) = 1;
  my $ready = select($rin, undef, undef, $seconds);
  return '' if !defined $ready || $ready <= 0;
  local $/ = "\n";
  my $line = <$handle>;
  return undef unless defined $line;
  return $line;
}
my $settled = 0;
while (!$settled) {
  report_main_exit();
  my $line = read_control_line($sock, 0.2);
  last unless defined $line;
  next if $line eq '';
  chomp $line;
  if ($line eq 'term') {
    run_graceful_hook(
      $sock,
      $marker,
      $opt{graceful},
      $opt{graceful_timeout},
    );
    kill 15, 0;
    kill 18, 0;
    print $sock "term-forwarded\n";
    $sock->flush();
  } elsif ($line eq 'kill') {
    print $sock "killed-group\n";
    $sock->flush();
    kill 9, 0;
  } elsif ($line eq 'settle') {
    print $sock "settled\n";
    $sock->flush();
    $settled = 1;
  }
}

unless ($settled) {
  kill 9, 0;
  eval { print $sock "unsettled:host-eof\n"; $sock->flush(); };
  exit(1);
}

if (!$main_reported) {
  my $reaped = waitpid($child, WNOHANG());
  if ($reaped > 0) {
    $main_status = $?;
    $main_reported = 1;
  }
}

my $status = $main_reported ? $main_status : 0;
if ($status & 127) {
  my $sig = $status & 127;
  $SIG{$sig} = 'DEFAULT';
  kill $sig, $$;
  exit(128 + $sig);
}
exit($status >> 8);
