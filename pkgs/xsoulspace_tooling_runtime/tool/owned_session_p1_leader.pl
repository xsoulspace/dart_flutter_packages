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

sub run_graceful_hook_child {
  my ($sock, $marker, $hook, $timeout_secs) = @_;
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
  elsif ($key eq '--graceful-timeout') {
    my $raw = shift @ARGV;
    my $marker = $opt{marker} || '';
    emit_error($marker, 'args', 'graceful-timeout')
      unless defined $raw && $raw =~ /^[0-9]+$/ && $raw >= 1 && $raw <= 300;
    $opt{graceful_timeout} = 0 + $raw;
  }
  elsif ($key eq '--') { last; }
  else {
    my $marker = $opt{marker} || '';
    emit_error($marker, 'args', "unknown-flag:$key");
  }
}

my $marker = $opt{marker} || emit_error('', 'args', 'marker');
emit_error($marker, 'protocol', 'version') unless ($opt{protocol} || '') eq '1';
emit_error($marker, 'mode', 'owned') unless ($opt{mode} || '') eq 'owned';
my $ctl_path = $opt{control} || emit_error($marker, 'control', 'path');

select STDERR; $| = 1;
$SIG{PIPE} = 'IGNORE';

my $sid = POSIX::setsid();
emit_error($marker, 'setsid', $! + 0) if !defined $sid || $sid < 0;
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

open(STDIN, '<', '/dev/null') or emit_error($marker, 'stdin', $! + 0);

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

my $settled = 0;
my $killed = 0;
my $term_requested = 0;
my $term_forwarded = 0;
my $hook_pid = 0;
my $control_buf = '';

sub forward_term_group {
  my ($sock) = @_;
  kill 15, 0;
  kill 18, 0;
  print $sock "term-forwarded\n";
  $sock->flush();
  $term_forwarded = 1;
}

sub kill_group {
  my ($sock) = @_;
  print $sock "killed-group\n";
  $sock->flush();
  kill 9, 0;
  $killed = 1;
}

sub stop_hook_child {
  return unless $hook_pid;
  kill 9, $hook_pid;
  waitpid($hook_pid, 0);
  $hook_pid = 0;
}

sub reap_hook_child {
  return unless $hook_pid;
  my $reaped = waitpid($hook_pid, WNOHANG());
  $hook_pid = 0 if $reaped > 0;
}

sub maybe_forward_term {
  return if $term_forwarded || !$term_requested || $killed;
  return if $hook_pid;
  forward_term_group($sock);
}

sub start_graceful_hook {
  return if $hook_pid;
  return unless defined $opt{graceful} && length $opt{graceful};
  my $hpid = fork();
  emit_error($marker, 'fork', $! + 0) unless defined $hpid;
  if ($hpid == 0) {
    run_graceful_hook_child(
      $sock,
      $marker,
      $opt{graceful},
      $opt{graceful_timeout},
    );
    exit(0);
  }
  $hook_pid = $hpid;
}

sub dispatch_control_line {
  my ($line) = @_;
  return if $killed || $settled;
  if ($line eq 'term') {
    $term_requested = 1;
    start_graceful_hook();
    maybe_forward_term();
  } elsif ($line eq 'kill') {
    stop_hook_child();
    kill_group($sock);
  } elsif ($line eq 'settle') {
    print $sock "settled\n";
    $sock->flush();
    $settled = 1;
  }
}

sub pump_control {
  my ($timeout) = @_;
  while ($control_buf =~ s/^([^\n]*)\n//) {
    dispatch_control_line($1);
    return 1 if $killed || $settled;
  }
  my $rin = '';
  vec($rin, fileno($sock), 1) = 1;
  my $ready = select($rin, undef, undef, $timeout);
  return 0 if !defined $ready || $ready <= 0;
  my $chunk = '';
  my $read = sysread($sock, $chunk, 4096);
  return -1 if !defined $read || $read == 0;
  $control_buf .= $chunk;
  while ($control_buf =~ s/^([^\n]*)\n//) {
    dispatch_control_line($1);
    return 1 if $killed || $settled;
  }
  return 0;
}

while (!$settled && !$killed) {
  report_main_exit();
  reap_hook_child();
  maybe_forward_term();
  my $pumped = pump_control(0.2);
  last if $pumped < 0;
}

unless ($settled) {
  stop_hook_child();
  kill 9, 0 unless $killed;
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
  kill $sig, $$;
  exit(128 + $sig);
}
exit($status >> 8);
