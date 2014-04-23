#!/usr/bin/perl

use warnings;
use strict;

my $part = shift;

my $title = <>;
print "# $title";

while(<>) {
    if (/^   (.+)$/) {
	print "\n## $1";
	while (<>) {
	    last if(/^$/);
	    s/\s+//;
	    print;
	}
	print "\n\n";
    } elsif (/^  (.+)$/) {
	print "\n### $1\n\n";
    } elsif (/^▼(リスト .+)$/) {
	print "\n";
	print "### $1";
	$_ = <>;
	if (/^(　)+\s+(.+)$/) {
	    print $1;
	    print "\n```\n";
	} else {
	    print "\n```\n";
	    print;
	}
	while (<>) {
	    last if (/^$/);
	    print;
	}
	print "```\n\n";
    } elsif (/^▼図 (\d+)\s+(.+)$/) {
	print "\n![$2](figures/part${part}_fig$1.png \"図$1\")\n\n";
    } elsif (/^注 ?(\d+) ?\) (.+)$/) {
	print "\n[^$1]: $2";
	while (<>) {
	    last if(/^$/);
	    if (/^注 ?(\d+) ?\) (.+)$/){
		print "\n[^$1]: $2";
		next;
	    }
	    chomp;
	    s/^(　)+//;
	    s/^\s+//;
	    print;
	}
	print "\n";
    } elsif (/^(①|②|③|④|⑤|⑥|⑦|⑧|⑨) (.+)$/) {
	print "\n" if ($1 eq "①");
	print chr(ord(substr($1,2))+ord("1")-ord(substr("①",2))),". $2";
	while (<>) {
	    if (/^$/) {
		print "\n\n";
		last;
	    }
	    if (/^(①|②|③|④|⑤|⑥|⑦|⑧|⑨) (.+)$/) {
		print "\n", chr(ord(substr($1,2))+ord("1")-ord(substr("①",2))),". $2";
	    } else {
		s/^\s+//;
		chomp;
		print;
	    }
	}
    } elsif (s/注(\d+)/[^$1]/ || s/図(\d+)/図[fig$1]/ ||
	     s/表(\d+)/表[tab$1]/) {
	print;
    } else {
	s/^\s+//;
	print;
    }
}

print << 'EOM';
ライセンス
==========

Copyright (c) 2014 Takuya ASADA. 全ての原稿データ は
クリエイティブ・コモンズ 表示 - 継承 4.0 国際
ライセンスの下に提供されています。
EOM
