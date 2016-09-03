#!/usr/bin/perl

use JSON;

# $json = '{"json": 123}';
# $j = decode_json($json);
# print $j->{json} . "\n";
# $jjj = encode_json($j);
# print "$jjj\n";

my $id;
my $myc1;
my $myc2;
my $opc1;
my $opc2;

# if($ARGV[0] eq 'standalone') {
# 	print "standalone\n";
# 	init();
# }

sub init() {
	# Запускается в самом начале, перед обработкой макросов
	$content = start('{"id": "123", "ft": true, "board": {"width": 4, "height": 4, "figures_count": 4, "cells": [[0,0,1,1],[1,1,2,2],[1,1,2,3],[3,3,3,3]]}}');
	my $j = decode_json(loadrootfile("games/$ip/$id"));
	my $json = encode_json($j);
	print "ok $ip - $j - $json\n";
}

sub _add_neighbour($$$) {
	my $j = shift;
	my $fig = shift;
	my $nei = shift;

	if($nei != $fig) {
		if(!defined($j->{board}{figures}[$fig]{neighbour}{$nei})) {
			$j->{board}{figures}[$fig]{neighbours}++;
			$j->{board}{figures}[$fig]{neighbour}{$nei} = 1;
		}
	}
}

# free - just free
# ffa - free for all potentially can be taken by all
# fmy - actually my

sub _sort($) {
	my $j = shift;

	my $w;
	my $h;

	my $c;
	my $i;
	my $k;

	my @a;

	# set only free
	undef $j->{free};

	for($c = 0; $c < $figures_count; $c++) {
		if($j->{figures}[$c]{color} == -1) {
			$j->{free}{$c} = 1;
		}
	}

# 	for($w = 0; $w < $j->{width}; $w++) {
# 		for($h = 0; $h < $j->{height}; $h++) {
# 			if($j->{}) {
#
# 			}
# 		}
# 	}

	# set only available for all
	undef $j->{ffa};

	undef @a; $a[0] = 0; $a[1] = 0; $a[2] = 0; $a[3] = 0;

	for($c = 0; $c < $figures_count; $c++) {
		$a[$j->{figures}[$c]{color}] = 1;
	}

	unless($a[0] && $a[1] && $a[2] && $a[3]) {
		$j->{ffa}{$c} = 1;
	}

	# set fact.my
	undef $j->{fmy};

	for($c = 0; $c < $figures_count; $c++) {
		if($j->{figures}[$c]{ismy}) {
			$j->{fmy}{$c} = 1;
		}
	}

	# set teor.my + teor.color
	undef $j->{tmy};

	undef @a; $a[0] = 0; $a[1] = 0; $a[2] = 0; $a[3] = 0;

	for($c = 0; $c < $figures_count; $c++) {
		$a[$j->{figures}[$c]{color}] = 1;
	}

	unless($a[$opc1] && $a[$opc2] && (!$a[$myc2] || !$a[$myc1])) {
		$j->{tmy}{$c} = 1;
	}

	# set threshold by calculating all free sizes middle/15 or 20 or 10 ... test it

	# set potential.my (surrounded) + color
	undef $j->{pmy};

	foreach $k (keys %{$j->{ffa}}) {
		unless($j->{tmy}{$k}) {
			$j->{pmy}{$k} = 1;
		}
	}
}

sub start($) {
	my $json = shift;
	my $j = decode_json($json);
	my $c;
	my $w;
	my $h;
	my $fig;

	$id = $j->{id};

	if($id =~ /^\w+$/) {
		if(!-d "$ROOTPATH/games") {
			mkdir("$ROOTPATH/games");
		}
		if(!-d "$ROOTPATH/games/$ip") {
			mkdir("$ROOTPATH/games/$ip");
		}
		for($c = 0; $c < $j->{board}{figures_count}; $c++) {
			$j->{board}{figures}[$c]{color} = -1;
			$j->{board}{figures}[$c]{neighbours} = 0;
		}
		for($w = 0; $w < $j->{board}{width}; $w++) {
			for($h = 0; $h < $j->{board}{height}; $h++) {
				$fig = $j->{board}{cells}[$h][$w];
				$j->{board}{figures}[$fig]{size}++;
				if($h > 0) {
					_add_neighbour($j, $fig, $j->{board}{cells}[$h - 1][$w]);
				}
				if($h < $j->{board}{height} - 1) {
					_add_neighbour($j, $fig, $j->{board}{cells}[$h + 1][$w]);
				}
				if($w > 0) {
					_add_neighbour($j, $fig, $j->{board}{cells}[$h][$w - 1]);
				}
				if($w < $j->{board}{width} - 1) {
					_add_neighbour($j, $fig, $j->{board}{cells}[$h][$w + 1]);
				}
				if($h % 2) {
					if($h > 0 && $w < $j->{board}{width} - 1) {
						_add_neighbour($j, $fig, $j->{board}{cells}[$h - 1][$w + 1]);
					}
					if($h < $j->{board}{height} - 1 && $w < $j->{board}{width} - 1) {
						_add_neighbour($j, $fig, $j->{board}{cells}[$h + 1][$w + 1]);
					}
				}else{
					if($h > 0 && $w > 0) {
						_add_neighbour($j, $fig, $j->{board}{cells}[$h - 1][$w - 1]);
					}
					if($h < $j->{board}{height} - 1 && $w > 0) {
						_add_neighbour($j, $fig, $j->{board}{cells}[$h + 1][$w - 1]);
					}
				}
			}
		}
		saverootfile("games/$ip/$id", encode_json($j->{board}));
	}

	return '{"status": "ok", "figure": 1}';
}

1;

# Это движок :) Счас опишу его немного:
#
# 1) В этот файл пишем, в *oblk.pl - только конфигурируем
# 2) В этом движке есть ТОЛЬКО макросы, кроме макросов нет ничего
# 3) Макросы вставляются в html
# Макросы (только основные):
# <!--func имя_функции--> - Запустит функцию из этого файла, функция должна выглядеть так:
# $func{имя_функции} = sub() {
# 	Тело функции;
# 	return значение;
# };
# Сам макрос заменится на возвращенное из функции ретурном значение
# <!--ajax имя_функции--> - Тоже самое что и func, но выдаст ответ в text/plain и без дизайна, только то, что вернет ретурн
# <!--formdata ключ--> - Напишет содержимое хеша $formdata{ключ}
# <!--rmifdata ключ--> html <!--/rmifdata ключ--> - удалит все что в этих тегах, если $formdata{ключ} не ложь
# 4) $formdata{ключ} - содержит значения данных GET и POST всех вместе
# 5) Работа с файлами только через функции loadrootfile, saverootfile - для обычных файлов в папке рут, и для временных файлов функция savetmpfile - это потому что движок потенциально на оперативке и файлы сохраняются одновременно в оперативку и на диск. Можно пользоваться и стандартыми перловыми open/close, но лучше моими т.к. оперативка
# 6) parse_tohash - спарсить строку в хеш. parse_fromhash - хеш в строку, запускается так: parse_fromhash(\%hash) - обязательно слеш перед % (это передает хеш по ссылке, так надо :) parse_tohash вернет ссылку на хеш, т.е. $var = parse_tohash($str); $val = $var->{key}
# 7) setcookie - ставит куки, а хеш %cookie - клиентские куки
# 8) mutex/unmutex - блокирует работу всех паралельных копий этого процесса
# 9) Всё :)
