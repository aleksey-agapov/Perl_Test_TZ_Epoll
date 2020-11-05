#!/perl -l
use IO::Socket::INET;
use Getopt::Long;

sub EAGAIN() {11}
sub TCP_KEEPIDLE() {4}
sub TCP_KEEPINTVL() {5}
sub TCP_KEEPCNT() {6}
use Socket qw(IPPROTO_TCP );

use strict;
use EPW;
use JSON::XS;
use utf8;
use Gzip::Faster;




my$S;
my%clientBuf;

my%sn2Rate=(
    1=>10,
    2=>25,
    3=>50);




my $crypt = 0;

GetOptions(
        "crypt"         => \$crypt,
);


sub logg
{
        print localtime()." @_";
#        print O localtime()." @_";
}


sub newClient
{
    my$c=$S->accept();
    return unless $c;
    
   $c->blocking(1);  # 0
	$c->autoflush(1);

    $c->setsockopt(IPPROTO_TCP,TCP_KEEPIDLE,100);
    $c->setsockopt(IPPROTO_TCP,TCP_KEEPINTVL,30);
    $c->setsockopt(IPPROTO_TCP,TCP_KEEPCNT,5);
    $c->setsockopt(SOL_SOCKET,SO_KEEPALIVE,1);
    $clientBuf{$c}=[new JSON::XS,''];
    
    logg "+client #".fileno($c)." ".inet_ntoa((sockaddr_in $c->peername())[1]);
#    send  ($c,"\r\n",0);#only small message
   if ($crypt) {
     send  ($c,gzip ("\r\n"),0);
   } else {
      send  ($c,"\r\n",0);
   }
    EPW::setFDH($c,\&processClientReq,\&sendReply,\&clientErr,undef);
}

sub clientErr
{
	logg "Client error:";
    dropClient(shift);
}



sub ServerErr
{
    logg "Server error:";
}
=doc  zzzzz
sub processClientReqZ
{
    my($c)=@_;

    my $read_buffer = "";
    my $input_stream = "";
    my $rv = 0;
    
    my$recv_size=1; # 1
    my $zero_count = 0;
    
    my @cmd_buffer = ();

    while ($recv_size > 0 ) {
    	$recv_size = sysread($c,$read_buffer,4096);
    	logg "recv_size: $recv_size  read_buffer: $read_buffer";
    	if (defined($recv_size) ) {
	    	$input_stream.=$read_buffer;
	    	$rv+=$recv_size;
	    	if ($recv_size == 4096) {
	    		continue;
	    	} elsif ($recv_size == 0) {
	    		logg "processClientReq: read:$rv byte";
	    		last;
	    	}
	    	
	    	push (@cmd_buffer, $input_stream);
	    	logg "processClientReq: read:$rv byte";
	    	$input_stream = "";
    	} else {
    		logg "processClientReq: socket error. read_size: $rv";
    		last;
    	}
    }

    if($rv==0) {dropClient($c); die  "Error Not input data!"}

    
    while (scalar(@cmd_buffer) > 0) {
    	my$dt = "";
    	my @socket_record_list = split('\n', shift(@cmd_buffer));
    	while (scalar (@socket_record_list)) {
	    	my $socket_stream_record = shift (@socket_record_list);
	    	if (!defined($socket_stream_record) || ($socket_stream_record eq "") ) {
	    		continue;
	    	}
	    	
		    my $ret0 = eval {$dt=gunzip($socket_stream_record);1};
		    unless ($ret0 && defined($dt)) {
#		    	dropClient($c);
		    	die  "Error to decode input data! $@";
		    }
		    
		    logg "processClientReq: read_from queue:$dt";
		    
		    my $ret1 = eval{
		    	$clientBuf{$c}[0]->incr_parse($dt);1
		    };
		    unless ($ret1) {
		        my$msg="wrong json <$dt>: $@";
		        chomp($msg);
		        $msg=~s/\n/\\n/g;
#		        dropClient($c);
		        die $msg;
		    }
		
		    my$obj;
		    my$ee=eval{$obj=$clientBuf{$c}[0]->incr_parse();1};
		    unless($ee)
		    {
		        my$msg="wrong json <$dt>: $@";
		        chomp($msg);
		        $msg=~s/\n/\\n/g;
#		        dropClient($c);
		        die $msg;
		    }
		    
		    my$pe=eval{process($c,$obj);1};
		    unless($pe)
		    {
		        my$msg="processing fail <$dt>: $@";
		        chomp($msg);
		        $msg=~s/\n/\\n/g;
#		        dropClient($c);
		        die $msg;
		    }
    	}
    }
    
#    if(length($clientBuf{$c}[1]))
#        {
#                EPW::setFDH($c,undef,\&sendReply,\&clientErr,undef); #     
#                return
#                
#        }
}

=cut

sub processClientReq
{
    my($c)=@_;

    my $read_buffer = "";

    my $recv_size = sysread($c,$read_buffer,4096);

    	if ( (!defined($recv_size) ) || ($recv_size==0) ||  ($read_buffer eq "") ) { die  "Error Not input data!"}   # {dropClient($c); die  "Error Not input data!"}
    	if ($crypt) {
    		logg "recv_size: $recv_size";
    	} else {
    		logg "recv_size: $recv_size read_buffer:$read_buffer";
    	}

		my $ret0 = 1;
    	my$dt = "";
    	
    	if ($crypt) {
    		$ret0 = eval {$dt=gunzip($read_buffer);1};
    	} else {
    		$dt=$read_buffer
    	}

		unless ($ret0) {
			dropClient($c);
			die  "Error to decode input data:$dt! $@";
		}
#    /}\s*,\s*{/
    	my @socket_record_list = split(/\n/, $dt);
    	while (scalar (@socket_record_list) > 0) {
	    	my $socket_stream_record = shift (@socket_record_list);
	    	
	    	unless (defined($socket_stream_record) && ($socket_stream_record ne "") ) {
	    		logg "processClientReq: next:";
	    		continue;
	    	}

		    logg "processClientReq: read_from queue:$socket_stream_record";
		    
		    my $ret1 = eval{
		    	$clientBuf{$c}[0]->incr_parse($socket_stream_record);1
		    };
		    unless ($ret1) {
		        my$msg="wrong json <$socket_stream_record>: $@";
		        chomp($msg);
		        $msg=~s/\n/\\n/g;
#		        dropClient($c);
		        die $msg;
		    }
		
		    my$obj;
		    my$ee=eval{$obj=$clientBuf{$c}[0]->incr_parse();1};
		    unless($ee)
		    {
		        my$msg="wrong json <$socket_stream_record>: $@";
		        chomp($msg);
		        $msg=~s/\n/\\n/g;
#		        dropClient($c);
		        die $msg;
		    }
		    
		    my$pe=eval{process($c,$obj);1};
		    unless($pe)
		    {
		        my$msg="processing fail <$socket_stream_record>: $@";
		        chomp($msg);
		        $msg=~s/\n/\\n/g;
#		        dropClient($c);
		        die $msg;
		    }
    	}
    
#    if(length($clientBuf{$c}[1]))
#        {
#                EPW::setFDH($c,undef,\&sendReply,\&clientErr,undef); #     
#                return
#                
#        }
    

    
}





sub sendReply
{
    my($c)=@_;
    
    if(length($clientBuf{$c}[1])) {
    
	    my$bytes=send ($c,$clientBuf{$c}[1],0);

		if (defined($bytes) && ($bytes>0) )  {
		       logg "sendReply>$bytes";
		    if( (length($clientBuf{$c}[1])==$bytes) || ($bytes == 0) )
		    {
   if ($crypt) {
     send  ($c,gzip ("\r\n"),0);
   } else {
      send  ($c,"\r\n",0);
   }
		        $clientBuf{$c}[1]="";
		        EPW::setFDH($c,\&processClientReq,undef,\&clientErr,undef);
		    }else
		    {
		        $clientBuf{$c}[1]=substr($clientBuf{$c}[1],$bytes);
		        EPW::setFDH($c,undef,\&sendReply,\&clientErr,undef);
		    }
		} else {
			dropClient($c);
			die "Socket close!";
		}
	
    } else {
    	EPW::setFDH($c,\&processClientReq,undef,\&clientErr,undef);
    }
}

sub reply
{
   my($c,$obj)=@_;
   my $ret_str = encode_json($obj);
   my $dt;
   if ($crypt) {
      $dt=gzip ($ret_str);
   } else {
      $dt= $ret_str;
   }
   my$pref=$$obj{ans};
   logg ">c#".fileno($c)."[$pref]: $ret_str";

   if(length($clientBuf{$c}[1]))
   {
        $clientBuf{$c}[1].=$dt;
        logg "==> Add to send buffer:".$ret_str;
   } else {
        $clientBuf{$c}[1]=$dt;
   }


        my $bytes=send ($c,$clientBuf{$c}[1], 0 );  # MSG_OOB
		if (defined($bytes) && ($bytes > 0) ) {
	        logg "==> Send byte:" . $bytes;
	        if($bytes<length($clientBuf{$c}[1]))
	        {
	        	$clientBuf{$c}[1]=substr($clientBuf{$c}[1],$bytes);
		        EPW::setFDH($c,\&processClientReq,\&sendReply,\&clientErr,undef); 
	        } else {
	        	
   if ($crypt) {
     send  ($c,gzip ("\r\n"),0);
   } else {
      send  ($c,"\r\n",0);
   }
	        	
#	        	
	        	$clientBuf{$c}[1]=''; 
	        	EPW::setFDH($c,\&processClientReq,undef,\&clientErr,undef);
	        }
		}
		else {
			dropClient($c);
			die "Socket close!";
		}
}

sub process
{
    my($c,$obj)=@_;
    
    if (!defined($obj) ) {
    	dropClient($c);
    	die "Error Not intut data fo process!!!";
    }
    
    my$pref=$$obj{req};
    eval { logg "<c#".fileno($c)."[$pref]: ".encode_json($obj);    };
    if ($@) {
    	die "Error log process args: $@";
    }

    my($type)=$$obj{req};
    if($type eq 'verify')
    {
        my($point,$ccode)=@$obj{'id','code'};
        verify($c,$point,$ccode);
    }elsif($type eq 'prepare')
    {
        calc($c,$obj);
        
    }elsif($type eq 'close')
    {
        fin($c,$obj);
    }elsif($type eq 'closed')
    {
        my$billId=$$obj{id};
        dummyClosed($c,$billId);
    }else
    {
    	dropClient($c);
        die "wrong type $type";
    }
}

sub verify
{
    my($c,$point,$ccode)=@_;
    my$result;
    unless($ccode=~/^cl(?:b|\d\d)\d{7,}/)
    {
        $result={ans=>'unknown',code=>$ccode};
    }else
    {
        my%opt=verify_onFile($ccode);
        if(!%opt || $opt{closed})
        {
            $result={ans=>'coupon',state=>'invalid',code=>$ccode};
        }else
        {
            $result={ans=>'coupon',state=>'valid',code=>$ccode};
        }
    }
    reply($c,$result)
}

sub fin
{
    my($c,$obj)=@_;
    for my$cp(@{$$obj{coupons}})
    {
        my%opt=verify_onFile($cp);
        close_onFile($cp) if $sn2Rate{$opt{id}};
    }
    reply($c,{ans=>'close',id=>$$obj{id}});
}

sub dummyClosed
{
    my($c,$id)=@_;
    reply($c,{ans=>'closed',id=>$id})
}


sub calc
{
    my($c,$obj)=@_;
    my@discs;
    for my$cp(@{$$obj{coupons}})
    {
        my%opt=verify_onFile($cp);
        my$rate =$sn2Rate{$opt{id}};
        next unless $rate;
        for my$p (@{$$obj{items}})
        {
            next if $$p{exclude};
            push @discs,{
                num=>$$p{num},
                discount=>$$p{cost}*$$p{amount}*$rate/100+$$p{discount},
                code=>$opt{aId}};
        }
    }
    my$r={
        ans=>'discount',id=>$$obj{id},
        discount=>\@discs
    };
    reply($c,$r);
}



sub dropClient
{
    my$c=shift;
    delete($clientBuf{$c});
    EPW::clearFDH($c);
    
    eval {
    	logg "-client #".fileno($c);
	    shutdown($c,2);
	    close $c;
    };
    logg " ================================================================================================ " 
}

sub verify_onFile
{
    my($code)=@_;
    $code=~/^cl(b|\d\d)(\d\d\d)(\d\d\d)(\d+)/ or return;

    my$iCode="$1-$2-$3-$4";
    my$F;
    open $F,"<","cps/$iCode.data" or return;
    my%opt;
    while(<$F>)
    {
        if(/^\s*(id|weight|closed|aId)=(.*)/)
        {
            $opt{$1}=$2;
        }
        last if /\@Coupon\[registered\]:.End$/i;
    }
    return %opt;
}
sub close_onFile
{
    my($code)=@_;
    $code=~/^cl(b|\d\d)(\d\d\d)(\d\d\d)(\d+)/ or logg ("close <$code> failed"),return;
    my$iCode="$1-$2-$3-$4";
    logg "coupon $iCode closed";
    my$F;
    open $F,'>>',"cps/$iCode.data" or logg("close-open <$iCode> failed"),return;
    print $F "closed=1";
    close $F;
}


open O,'>>test.log';
select+((select O),$|=1)[0];


$S=new IO::Socket::INET(Listen=>3,ReuseAddr=>1,LocalPort=>1212) or die "bindErr: $!";
EPW::setFDH($S,\&newClient,\&ServerErr,undef);
EPW::loo();

