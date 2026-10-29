#!/usr/bin/env perl
# 应用派生的独立进程持有 OS 文件锁；EOF 或 release 均释放。
use strict;
use warnings;
use Fcntl qw(:flock);
$| = 1;
open(my $lock, '>>', $ARGV[0]) or die "无法打开合成锁文件\n";
flock($lock, LOCK_EX) or die "无法取得合成锁\n";
print "locked:$$\n";
my $release = <STDIN>;
flock($lock, LOCK_UN) or die "无法释放合成锁\n";
print "released\n";
close($lock);
