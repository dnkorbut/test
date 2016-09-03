#!/usr/bin/perl

# ALERT ram

use strict;
use Socket qw(:all);
use Fcntl qw(:flock);
use Time::HiRes qw(gettimeofday tv_interval); # ALERT hires

### Основная конфигурация

our $WORKDIR = './';

my $SERVER_PORT = 9002;
my $MAX_WORKERS = 30;

# my $CLI_TIMEOUT_SEC = 15;

our $MAX_POST = 10; # in Mb
our $maxup_kb = $MAX_POST;

my $EMAIL = 'webmaster@oblk.org';

my $ROOTNAME = "";
my $WEBNAME = "";
my $BACKUPNAME = "";
# my $ROOTNAME = "root";
# my $WEBNAME = "web";
# my $BACKUPNAME = "rd/root";

our $ROOTPATH = "$WORKDIR/$ROOTNAME";
our $BACKUPPATH = "$WORKDIR/$BACKUPNAME";
our $WEBPATH = "$WORKDIR/$WEBNAME";

our $allowed_symbols = '(\\w|ё|й|ц|у|к|е|н|г|ш|щ|з|х|ъ|ф|ы|в|а|п|р|о|л|д|ж|э|я|ч|с|м|и|т|ь|б|ю|Ё|Й|Ц|У|К|Е|Н|Г|Ш|Щ|З|Х|Ъ|Ф|Ы|В|А|П|Р|О|Л|Д|Ж|Э|Я|Ч|С|М|И|Т|Ь|Б|Ю|і|І|Ї|ї|є|Ґ|ґ|Є)';

my $SENDMAIL = '/usr/sbin/sendmail';

my $HTTP_IP = "X\-Real\-IP: ";

my $HTTP_COOKIE_END = 'path=/; expires=Wed, 25 Mar 2099 07:07:37 GMT'; # default

### Основная конфигурация закончена

my $HTTP_HEADER_200 = "HTTP/1.0 200 OK\n";
my $HTTP_HEADER_303 = "HTTP/1.0 303 See Other\nLocation: redirecto\n";
my $HTTP_HEADER_404 = "HTTP/1.0 404 Not Found\n";
my $HTTP_HEADER_501 = "HTTP/1.0 501 Not Implemented\n";
my $HTTP_HEADER_EMPTY = "\n";
my $HTTP_HEADER_HTML = "Content-type: text/html\n\n";
my $HTTP_HEADER_TEXT = "Content-type: text/plain\n\n";
my $HTTP_HEADER_JSON = "Content-type: application/json\n\n";
my $HTTP_HEADER_E404 = "Content-type: text/html\n\n";
my $HTTP_HEADER_E501 = "\n";
my $HTTP_STATUS = $HTTP_HEADER_200;
my $HTTP_COOKIE = '';
my $HTTP_HEADER = $HTTP_STATUS . $HTTP_COOKIE . $HTTP_HEADER_HTML;

my $PUT = 0;
my $DELETE = 1;
my $POST = 2;
my $GET = 3;

my $child_pid;
my $c;
my $worker_id = $$; # 0 only on parent
my $workers_ready = 0;
our $mq; # mutex fd

my $sock;
my $client;

our $ruri = ''; # page/0/1/2/html (main: 'html')
our $rpath = ''; # page/0/1/2 (main: '')
our $rdatapath = ''; # data/page/0/1/2 (main: 'data')
our $ruri_path = ''; # page/0/1 (main '')
our $ruri_name = ''; # 2 (main: '')
our $rurl = ''; # page/0/1/2.html || page/0/1/2 (main: '')
our $header = '';
my $method = $GET;
my $post = '';
our %formdata;
our %multipart;
our %cookie;
our $ip;
our $ua;
my $buf;
my $contentlength = 0;
my $boundary = '';

my $design = '<!--content-->';
our $content = '';

our %func;

our @lang;
our $lid = 0;
our $t;

my $loadfileerror = 0;
my $loadfileerror_file = '';

# ajust to Mb
$MAX_POST *= 1024 * 1024;
$maxup_kb *= 1024; # to kb

# do "$WORKDIR/lang.pl" or die("$@: cant load lang.pl");
# do "$WORKDIR/oblk.pl" or die("$@: cant load oblk.pl");
do "$WORKDIR/site.pl" or die("$@: cant load site.pl");

print "start...\n";

socket($sock, PF_INET, SOCK_STREAM, getprotobyname('tcp')) or die ("Не могу создать сокет!");
setsockopt($sock, IPPROTO_TCP, TCP_NODELAY, 1);
setsockopt($sock, SOL_SOCKET, SO_REUSEADDR, 1);
bind($sock, sockaddr_in($SERVER_PORT, INADDR_ANY)) or die("Не могу привязать порт! $SERVER_PORT");
print "Ожидаем подключения...\n";
listen($sock, SOMAXCONN);

print "server ready...\n";

$workers_ready++;
savetmpfile("workers.txt", $workers_ready);
print "I $$ start\n";

sub stopit() { close($client); shutdown($client, 2); close($sock); shutdown($sock, 2); die "\n$$: I close\n"; }
$SIG{TERM} = \&stopit;

while($_ = accept($client, $sock)) {
  # setsockopt($client, SOL_SOCKET, SO_SNDTIMEO, pack('l!l!', $CLI_TIMEOUT_SEC, 0));
  # setsockopt($client, SOL_SOCKET, SO_RCVTIMEO, pack('l!l!', $CLI_TIMEOUT_SEC, 0));
  $ip = inet_ntoa((sockaddr_in($_))[1]);

  $workers_ready = workersadd(-1);

	if($workers_ready < 1) {
		$child_pid = fork();
		if(!$child_pid) {
			$worker_id = $$;
			print "New worker $$ created: $workers_ready\n";
			$workers_ready = workersadd(1);
			close $client;
			next;
		}
	}

	#eval { worker(); };
	worker();
	close $client;

	$workers_ready = workersadd(1);
	if($workers_ready > $MAX_WORKERS) {
		print "I $$ go down, since no more needed\n";
		#print `ps auxf | grep blender.pl`;
		print `pstree $$`;
		$workers_ready = workersadd(-1);
		exit;
	}
	#print "$$ ready [$workers_ready]\n";
	unmutex();
}

stopit();

sub worker() {
	undef %formdata;
	$formdata{_http_cookie_end} = $HTTP_COOKIE_END; # костыль, да
	undef %multipart;
	undef %cookie;
	#$ip = '127.0.0.200';
	$ua = '';
	$HTTP_COOKIE = '';
	$contentlength = 0;
	$boundary = '';
	$header = '';

	$_ = <$client>;
	if(/^(GET|POST|PUT|DELETE) \/(.*) HTTP\/[\d\.]+/) {
		$ruri = unescape($2);
		if($1 eq 'GET') {
			$method = $GET;
		}elsif($1 eq 'PUT') {
			$method = $PUT;
		}elsif($1 eq 'POST') {
			$method = $POST;
		}elsif($1 eq 'DELETE') {
			$method = $DELETE;
		}
	}else{
		print $client $HTTP_HEADER_501 . $HTTP_COOKIE . $HTTP_HEADER_E501;
		return;
	}

	if($ruri =~ s/\?(.+)//) {
		$post = $1;
		getpostdata();
	}

# 	$design = loadrootfile("design.html"); ### ### FIXME preload this

	### ### ruri
# 	$ruri =~ s/\/+$//;
# 	$rurl = $ruri;
# 	$ruri =~ s/\.html$//;
# 	$rpath = $ruri;
# 	$ruri_path = $ruri;
# 	if($ruri_path =~ s/\/*($allowed_symbols+)$//) {
# 		$ruri_name = $1;
# 	}else{
# 		$ruri_name = '';
# 	}
# 	$ruri .= '/html';
#
# 	if($ruri !~ /^($allowed_symbols*\/)*$allowed_symbols*$/) {
# 		notfound();
# 		return;
# 	}
#
# 	$rdatapath = 'data';
# 	if($rpath ne '') {
# 		$rdatapath .= "/$rpath";
# 	}
#
# 	if(!-f "$ROOTPATH/data/$ruri") {
# 		notfound();
# 		return;
# 	}
	### ### /ruri

	while(<$client>) {
		$header .= $_;
		if($_ =~ /^\s*$/) {
			last;
		}
		if($method == $POST && /^Content-Length: (\d+)/) {
			if($1 < $MAX_POST) {
				$contentlength = $1;
			}
		}elsif($method == $POST && /^Content-Type:\s*multipart\/form-data;.*\s*boundary=(\S+)/) {
			$boundary = $1;
		}elsif(/^$HTTP_IP(\S+)/) {
			$ip = $1;
		}elsif(/^User-Agent: (.*)/) {
			$ua = $1;
		}elsif(/^Cookie: (.+)/) {
			$post = $1;
			while($post =~ /(\w+)=([^&;\r\n]*)/g) {
				$cookie{$1} = unescape($2);
			}
		}
	}

	if($ip !~ /^\w+[\w\.\:]+$/) {
		return;
	}

	if($method == $POST && $contentlength) {
		read($client, $post, $contentlength);
		getpostdata();
	}

# 	$content = loadrootfile("data/$ruri");

	$HTTP_STATUS = $HTTP_HEADER_200;
# 	$HTTP_HEADER = $HTTP_HEADER_HTML;

	$t = time();

# 	oblk_init();
# 	macro();
#
# 	print $client $HTTP_STATUS . $HTTP_COOKIE . $HTTP_HEADER;
# 	if($method == $HEAD) {
# 		return;
# 	}
# 	print $client $design;

	init();

	print $client $HTTP_STATUS . $HTTP_HEADER_JSON . $content
}

sub workersadd($) {
	my $a = shift;
	my $m = mutex();
	my $w = loadrootfile('workers.txt');
	$w += $a;
	savetmpfile('workers.txt', $w);
	unmutex($m);
	return $w;
}

sub setcookie($$) {
	my $name = shift;
	my $value = iwescape(shift);

	$HTTP_COOKIE .= "Set-Cookie: $name=$value; $HTTP_COOKIE_END\n";
}

sub redirect303($) {
	my $redirecto = shift;
	$HTTP_STATUS = $HTTP_HEADER_303;
	$HTTP_STATUS =~ s/redirecto/$redirecto/g;
	$HTTP_HEADER = $HTTP_HEADER_HTML;
	$design = "<html><head><title>Redirect to $redirecto</title></head><body>You are being redirected to: <a href='$redirecto'>$redirecto</a></body></html>";
}

sub macro_killdesign() {
	$design = '<!--content-->';
	return '';
}

sub macro_rmifdata($) {
	my $chpost = shift;
	if($formdata{$chpost}) {
		$design =~ s/<!--rmifdata $chpost-->[\s\S]*<!--\/rmifdata $chpost-->//g or s/<!--\/*rmifdata $chpost-->//g;
	}else{
		$design =~ s/<!--\/*rmifdata $chpost-->//g;
	}
}

sub macro_ajax($) {
	my $ajaxname = shift;
	$HTTP_HEADER = $HTTP_HEADER_TEXT;
	macro_killdesign();
	$content =~ s/<!--ajax $ajaxname-->/if(defined($func{$ajaxname})) { $func{$ajaxname}->(); }/ge;
}

sub macro() {
	# AJAX should be first and "on content" macro since it kills design
	if($content =~ /<!--ajax (\w+)-->/) {
		macro_ajax($1);
	}

	# LAST oncontent macro
	$content =~ s/<!--killdesign-->/macro_killdesign();/ge;
	$design =~ s/<!--content-->/$content/g;

	$design =~ s/<!--func (\w+)-->/if(defined($func{$1})) { $func{$1}->(); }/ge;

	$design =~ s/<!--formdata (\w+)-->/$formdata{$1}/g;
	while($design =~ /<!--rmifdata (\w+)-->/) {
		macro_rmifdata($1);
	}

	$design =~ s/<!--lang (\w+)-->/$lang[$lid]{$1}/g;

	# $design =~ s/<!--var (\w+)-->/$vars{$1}/g;
}

sub replace_content($) {
	my $new = shift;
	$content = $new;
}

sub updatefile($$$$$) {
	my $path = shift;
	my $file = shift;
	my $tmp = shift;
	my $hash = shift;
	my $sub = shift;

	my $mutex = local_root_mutex($path);
	$$hash = parse_tohash(loadrootfile("$path/$file"));
	$sub->();
	if($tmp) {
		savetmpfile("$path/$file", parse_fromhash($$hash));
	}else{
		saverootfile("$path/$file", parse_fromhash($$hash));
	}
	local_root_unmutex($mutex);
}

sub notfound() {
	$design = '<!--content-->';
	$content = loadrootfile("404.html");

	macro();

	print $client $HTTP_HEADER_404 . $HTTP_COOKIE . $HTTP_HEADER_E404;

# 	if($method == $HEAD) {
# 		return;
# 	}

	print $client $design;
}

sub mutex() {
	open($mq, ">$ROOTPATH/mutex");
	if(!flock($mq, LOCK_EX|LOCK_NB)) { # ALERT hires
		my $hires = [gettimeofday];
		if(flock($mq, LOCK_EX)) {
			print "GLOB $$ wait " . sprintf("%.6f", tv_interval($hires, [gettimeofday])) . "\n";
		}else{
			die "DIED GLOB $$ mutex die";
		}
	}
}

sub unmutex() {
# 	flock($mq, LOCK_UN);
	close $mq;
}

sub local_root_mutex($) {
	my $path = shift;
	my $mutexq;

	open($mutexq, ">$ROOTPATH/$path/mutex");
	if(!flock($mutexq, LOCK_EX|LOCK_NB)) { # ALERT hires
		my $hires = [gettimeofday];
		if(flock($mutexq, LOCK_EX)) {
			print "LOCAL $$ $path wait " . sprintf("%.6f", tv_interval($hires, [gettimeofday])) . "\n";
		}else{
			die "DIED LOCAL $$ mutex die $path";
		}
	}

	return $mutexq;
}

sub local_root_unmutex($) {
	my $mutexq = shift;
	close $mutexq;
}

sub savetmpfile($$) {
	my $file = shift;
	my $content = shift;
	my $wq;

	if($loadfileerror && $loadfileerror_file eq $file) {
		appendtorootfile('ulog.txt', "<b class='im'>FILE TMP ERROR</b>: $file<br />\n");
		return;
	}

	if(open($wq, ">$ROOTPATH/$file")) {
		flock($wq, LOCK_EX);
		print $wq $content;
		close $wq;
	}
}

sub makerootdir($) {
	my $dir = shift;

	if(!-d "$ROOTPATH/$dir") {
		mkdir("$ROOTPATH/$dir");
	}
# 	if(!-d "$BACKUPPATH/$dir") {
# 		mkdir("$BACKUPPATH/$dir");
# 	}
}

sub saverootfile($$) {
	my $file = shift;
	my $content = shift;
	my $wq;

	if($loadfileerror && $loadfileerror_file eq $file) {
		appendtorootfile('ulog.txt', "<b class='im'>FILE ROOT ERROR</b>: $file<br />\n");
		return;
	}

	if(open($wq, ">$ROOTPATH/$file")) {
		flock($wq, LOCK_EX);
		print $wq $content;
		close $wq;
	}

	# ALERT ram
# 	if(open($wq, ">$BACKUPPATH/$file")) {
# 		flock($wq, LOCK_EX);
# 		print $wq $content;
# 		close $wq;
# 	}
}

sub appendtorootfile($$) {
	my $file = shift;
	my $content = shift;
	my $wq;

	if(open($wq, ">>$ROOTPATH/$file")) {
		flock($wq, LOCK_EX);
		print $wq $content;
		close $wq;
	}

	# ALERT ram
# 	if(open($wq, ">>$BACKUPPATH/$file")) {
# 		flock($wq, LOCK_EX);
# 		print $wq $content;
# 		close $wq;
# 	}
}

sub backupfile($) {
	my $f = shift;
	my $rq;
	my $wq;

	# ALERT ram
	if(open($rq, "<$ROOTPATH/$f")) {
		while(<$rq>) {
			print $wq $_;
		}
		close $rq;
		close $wq;
	}
}

sub parse_tohash($) {
	my $var = shift;
	my %hsh;

	while($var =~ /(\w+) = (.*\S)\s+/g) {
		$hsh{$1} = $2;
	}

	return \%hsh;
}

sub parse_fromhash(%) {
	my $hsh = shift;
	my $ret = '';
	my $key;

	for $key (keys %{$hsh}) {
		if($key =~ /^\w+$/) {
			$ret .= "$key = $hsh->{$key}\n";
		}
	}

	return $ret;
}

sub email($$$) {
	my $mailto = shift @_;
	my $subject = shift @_;
	my $body = shift @_;
	my $sendmailq;

	$subject =~ s/^([\s\S]{0,128})[\s\S]*$/$1/;
	$subject =~ s/(\r|)\n/ /g;
	$subject =~ s|(\W)|'=' . uc(unpack("H2", $1))|eg;
	$subject = '=?utf-8?Q?' . $subject . '?=';
	$mailto =~ s/\s+//g;
	$mailto =~ s/[\%\/:]//g;

	if(open($sendmailq, "|$SENDMAIL -t")) {
		print $sendmailq "From: $EMAIL\n";
		print $sendmailq "To: $mailto\n";
		print $sendmailq "Reply-To: $EMAIL\n";
		print $sendmailq "Subject: $subject\n";
		print $sendmailq "Content-Type: text/plain;\n\tcharset=\"utf-8\"\n\n";
		print $sendmailq $body;

		close $sendmailq;
	}
}

sub loadrootfile($) {
	my $file = shift;
	my $content = '';
	my $rq;

	if(open($rq, "<$ROOTPATH/$file")) {
		flock($rq, LOCK_EX);
		while(<$rq>) {
			$content .= $_;
		}
		flock($rq, LOCK_UN);
		close $rq;
		$loadfileerror = 0;
	}else{
		if(-f "$ROOTPATH/$file") {
			$loadfileerror = 1;
			$loadfileerror_file = $file;
		}
	}

	return $content;
}

sub getpostdata() {
	if($boundary) {
		my $buf;
		my $fieldname;
		$post =~ s/^([\s\S]*?)\Q--$boundary\E\r\n//;
		while($post =~ s/^([\s\S]*?)\r\n\r\n//) {
			$buf = $1;
			if($buf =~ /\sname="(\w+)"/) {
				$fieldname = $1;

				if($buf =~ /\sfilename="([^"]+)"/) {
					$multipart{$fieldname}{filename} = $1;
				}else{
					$multipart{$fieldname}{filename} = '';
				}
				if($buf =~ /Content-Type:\s+(.+)/) {
					$multipart{$fieldname}{contenttype} = $1;
				}else{
					$multipart{$fieldname}{contenttype} = '';
				}

				if($post =~ s/^([\s\S]*?)\r\n\Q--$boundary\E//) {
					$buf = $1;
					$formdata{$fieldname} = $buf;
				}
			}
		}
	}else{
		while($post =~ /(\w+)=([^&;\r\n]*)/g) {
			$formdata{$1} = unescape($2);
		}
	}
}

sub getrndpass() {
	my $buf;
	my $c;

	for($c = 0; $c < 32; $c++) {
		$buf .= (0..9, 'A'..'Z', 'a'..'z')[rand 62];
	}

	return $buf;
}

sub iwescape($) {
	my $ret = shift @_;
	$ret =~ s|(\W)|'%' . uc(unpack("H2", $1))|eg;
	return $ret;
}

sub unescape($) {
	my $param = shift @_;

	$param =~ y/+/ /;
	$param =~ s/\%\%/\%25/g;
	$param =~ s/%([a-f\d][a-f\d])/chr(hex($1))/egi;

	return $param;
}

sub dehtml($) {
	my $param = shift @_;

	$param =~ s/&/&amp;/g;
	$param =~ s/</&lt;/g;
	$param =~ s/>/&gt;/g;
	$param =~ s/"/&quot;/g;
	$param =~ s/'/&#39;/g;

	return $param;
}

sub unbase64($) {
	my $a = shift;
	my $r = '';

	$a =~ s/^.*?base64,//;
	$a =~ tr#A-Za-z0-9+/# -_#;
	$r .= unpack('u', pack('C', 32 + int(length($1) * 6 / 8)) . $1) while($a =~ s/(.{60}|.+)//);

	return $r;
}

1;
