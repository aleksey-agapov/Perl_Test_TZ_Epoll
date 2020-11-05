#!/perl -l
use IO::Socket::INET;
sub EAGAIN() {11}
sub TCP_KEEPIDLE() {4}
sub TCP_KEEPINTVL() {5}
sub TCP_KEEPCNT() {6}
use Socket qw(IPPROTO_TCP );

use strict;
use EPW;
use JSON::XS;
use utf8;

my$S;
my%clientBuf;

my%sn2Rate=(
    1=>10,
    2=>25,
    3=>50);

sub logg
{
        print O localtime()." @_";
}


sub newClient
{
    my$c=$S->accept();
    $c->blocking(0);
    return unless $c;
    logg "+client #".fileno($c)." ".inet_ntoa((sockaddr_in $c->peername())[1]);
    send $c,"\r\n",0;#only small message
    $c->setsockopt(IPPROTO_TCP,TCP_KEEPIDLE,100);
    $c->setsockopt(IPPROTO_TCP,TCP_KEEPINTVL,30);
    $c->setsockopt(IPPROTO_TCP,TCP_KEEPCNT,5);
    $c->setsockopt(SOL_SOCKET,SO_KEEPALIVE,1);
    $clientBuf{$c}=[new JSON::XS,''];
    EPW::setFDH($c,\&processClientReq,undef,\&clientErr,undef);
}

sub clientErr
{
    dropClient(shift);
}

sub processClientReq
{
    my($c)=@_;
    my$dt;
    my$rv=sysread($c,$dt,4096);
    if(defined($rv) && $rv==0)
    {
        if(length $clientBuf{$c}[1])
        {
                EPW::setFDH($c,undef,\&sendTo,\&clientErr,undef);
        }else
        {
            dropClient($c);
        }
        return
    }
    if((!defined($rv) && $!!=EAGAIN))
    {
        dropClient($c);
    }
    $clientBuf{$c}[0]->incr_parse($dt);

    my$obj;
    my$ee=eval{$obj=$clientBuf{$c}[0]->incr_parse();1};
    unless($ee)
    {
        my$msg="wrong json <$dt>: $@";
        chomp($msg);
        $msg=~s/\n/\\n/g;
        logg $msg;
        dropClient($c);
        last
    }
    my$pe=eval{process($c,$obj);1};
    unless($pe)
    {
        my$msg="processing fail <$dt>: $@";
        chomp($msg);
        $msg=~s/\n/\\n/g;
        logg $msg;
        dropClient($c);
    }
}

sub sendReply
{
    my($c)=@_;
    my$bytes=send$c,$clientBuf{$c}[1],0;
    if(length($clientBuf{$c}[1])==$bytes)
    {
        $clientBuf{$c}[1]='';
        EPW::setFDH($c,\&processClientReq,undef,\&clientErr,undef)
    }else
    {
        $clientBuf{$c}[1]=substr$clientBuf{$c}[1],$bytes
    }
}

sub reply
{
   my($c,$obj)=@_;
   my$dt=encode_json($obj);
   my$pref=$$obj{ans};
   logg ">c#".fileno($c)."[$pref]: $dt";
   $dt.="\r\n";
   if(length($clientBuf{$c}[1]))
   {
        $clientBuf{$c}[1].=$dt;
   }else
   {
        my$bytes=send$c,$dt,0;
        if($bytes<length$dt)
        {
            $clientBuf{$c}[1]=$dt;
            EPW::setFDH($c,\&processClientReq,\&sendReply,\&clientErr,undef);
        }
   }
}

sub process
{
    my($c,$obj)=@_;
    my$pref=$$obj{req};
    logg "<c#".fileno($c)."[$pref]: ".encode_json($obj);
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
    logg "-client #".fileno($c);
    EPW::clearFDH($c);
    shutdown($c,2);
    close $c;
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
EPW::setFDH($S,\&newClient,undef,undef);
EPW::loo();

