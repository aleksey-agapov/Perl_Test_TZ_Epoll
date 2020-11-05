package EPW;
use warnings;
use strict;
use IO::Epoll;
use Carp;
use Scalar::Util qw[openhandle looks_like_number reftype];
use Time::HiRes 'time';
use POSIX;


=pod
setFDH(h,readCB,writeCB,errCB,tag)
    (cb parameters = handle,tag
     on correct socket close readCB fired)
clearFDH(h)
setAT(cb,delay,tag)
cancelAT(cb,tag)
=cut



my $EPoll =epoll_create(100);
my (%h2cb);# id ->[cb]
my (%h2tag);#handle -> callTag
my ($interval,$tCB);#timeout callback
my $shouldStop=0;
my %fd2h;#fd number to original file object translation
my @scheduler; # [[time,code,tag],...] procedures should be run at specified(sec) time;


=doc
    set cb on {read/write/err}ready event
    handle may be glob ref or direct fileDescriptor(number)
    unused hanles should be undef
=cut
sub setFDH#(*&&&;$)
{
    my($handle,$readCB,$writeCB,$errCB,$tag)=@_;

    croak('handle should be opened stream or FD')
        unless openhandle$handle || looks_like_number$handle;
    croak("wrong CB, should be code reference or undef")
        if grep {defined $_ && (reftype($_)//'') ne 'CODE'}
            ($readCB,$writeCB,$errCB);
    
    my$action= EPOLL_CTL_MOD;
    my$fd=fileno($handle)//$handle;
    unless($h2cb{$handle})
    {
        $fd2h{$fd}=$handle;
        $action=EPOLL_CTL_ADD;
    }
    $h2tag{$handle}=$tag;
    $h2cb{$handle}=[$readCB,$writeCB,$errCB];

    my$mask=($errCB ? EPOLLERR:0)|
            ($readCB? EPOLLIN : 0)|($writeCB? EPOLLOUT : 0);

    my$er=epoll_ctl($EPoll,$action, $fd, $mask);
    #Trace $log 'try set mask='.$mask
}

=doc
    remove handlers from stream
=cut
sub clearFDH(*)
{
    my$handle=shift;
    my$fd=fileno($handle)//$handle;
    return
        unless $h2cb{$handle};
    epoll_ctl($EPoll,EPOLL_CTL_DEL, $fd,0);
    delete $h2cb{$handle};
    delete $h2tag{$handle};
    delete $fd2h{$fd};
}

=doc
    run code _after_ specified timeout
=cut
sub setAT(&$$)
{
    my($code,$interval,$tag)=@_;
    push @scheduler,[$interval+time,$code,$tag];
    @scheduler=sort{$$a[0] <=> $$b[0]}@scheduler;
}

=doc
    remove timeout
=cut
sub cancelAT(&$)
{
#TODO: faster algo
    my($code,$tag)=@_;
    my$i=0;
    for my$i(0..@scheduler)
    {
        splice(@scheduler,$i,1),return        
            if $scheduler[$i][1]==$code &&
               $scheduler[$i][2]==$tag;
    }
}

=doc
    (mainly for debugging)
    stop mainloop
=cut
sub fin()
{
    $shouldStop=1;
}

=doc 
    `main loop`
    wait events, call CB
    exited after fin()
=cut
sub loo()
{
   #$shouldStop=0;
    while(!$shouldStop)
    {
        my$delay=$scheduler[0]? (1000*($scheduler[0][0] -time())) : -1;
        my$rv=epoll_wait($EPoll,15,$delay);
        for my$h(@$rv)
        {
            my($fd,$mask)=@$h;
            my$handle=$fd2h{$fd};
            for my$kv(  [EPOLLERR,2],
                        [EPOLLIN|EPOLLHUP,0],
                        [EPOLLOUT,1],)
            {
                if($mask & $$kv[0])
                {
                    $mask=0 if($$kv[0]==EPOLLERR);
                    next unless $h2cb{$handle};
                    my$cb=$h2cb{$handle}[$$kv[1]];
                    unless(eval
                    {
                        &$cb($handle,$h2tag{$handle})
                            if $cb;
                        1
                    })
                    {
                        warn(err=>"clearin handle on die: $@");
                        clearFDH($handle);
                    }
                }
            }
        }
        my($i,$t)=(0,time);
        while($scheduler[$i] && $scheduler[$i][0]<=$t)
        {
            $scheduler[$i][1]->($scheduler[$i][2]);
            $i++;
        }
        splice @scheduler,0,$i;
    }
    $shouldStop=0;
}
1
