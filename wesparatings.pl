# Ratings Calculation
# Barry Harridge 3/04/2004
# Revised 12/01/2007
#
# Version 2 on uses provisional ratings
# and uses the chess way of calculating first rating
# Version 2.3 introduced checking ambiguous names like Joy Smith (a real pain!)
# Version 2.31 spits out the extra report
# Version 2.43 has headers for World and Nation, allows EXIT from the country tagging dialogue
# and uses ranking parameters of 3 years  and 50 games.
# Version 2.52 will use a 'from' file to answer questions about country
# It writes such a file so as to reuse the knowledge next try
# Version 2.53 is better suited for batch processing by relying on @ARGV parameters
# and a file of info about player origins
# Version 2.55 has at Edward's request, the STA file showing eg (560)   (560) for the change for a novice.
# It also tries to get an approximating linear rule for provisional players with parameters adjusted
# no matter what overall rule is used eg logit 172 etc
# Version 2.55 limits the opponent's rating for provisional players only
# in order to make the imputed probability between 0.05 and 0.95
# Version 2.55L copes with long tournaments by using k passes with multiplier m/k each time.
# Eg if the tournament has 45 rounds, and the variable $longlimit =20, it will use 3 passes.
# Version 2.56L imposes the floor at each pass rather than just at the end
# One reason is to fix the out of bounds error that occured for large $logitk
# NICKstateNAME                   06moonah.tou
# AFIS VIC Andrew Fisher         462 1880 20060910
# EOKU NSW Edward Okulicz       1503 1836 20060910
# CMAY NSW Chris May             841 1830 20060910
# NFER VIC Naween Fernando       661 1830 20060910

# Usage:   perl bazrat.pl 06LANG.TOU VIC 20060521
#                    ^         ^      ^
# TOU filename ------+         |      |
# State (VIC/NSW/etc) ---------+      |
# DATE  YYYYMMDD ---------------------+
# But if you omit parameters or give bad parameters you will be asked what to do

# Input files  : RATING.DAT assumed, 06LANG.TOU
# Output files : 06LANG.RT2 (can be used as RATING.DAT for next time)
#                06LANG.STA (stats file plus explanations)

#no warnings 'redefine';    # Kill annoying messages when called in a batch loop , puzzling will not work in perl2exe

$progname = 'WESPArat';

$version  = '3.14';
$probrule = 'logit';
$logitk   = 250;       # new default, May 2012

#$probrule = 'linear';
$lineark = 1200;

$k
  = ( $probrule eq 'logit' )
  ? 500 * $logitk / 172
  : $lineark / 2;      # eg linear 1200 -> 600 for provisional

$longlimit = 35
  ; # New default May 2012 Do two or more passes with fractional multiplier if tournament is longer than this

# basic parameters
@rlevel      = ( -9999, 1000, 1800, 2000, 9999 );
@rmultiplier = ( 30,    20,   16,   10,   1 );
$floor
  = 300;   # established ratings will not go below this , new default May 2012
$proviso = 50
  ;   # ratings are provisional (calculated differently) if less than XX games

$rankgames = 30;    # must have this many games to be ranked
$currency  = 2;     # rankings amongst players active in the last 2 years

$warntrigger = 100; # Report if score below this
$maxtol      = 30;
$maxtries    = 2;   # Will iterate this many times at most
$roofcap = 600;   # rating cannot go higher than opponents' mean rat + roofcap
     # possibly not needed now first rating is calculated differently

# Default unless set by a batch file
$ratext = 'RT1' unless ( defined($ratext) );    # New default May 2012
$staext = 'ST1' unless ( defined($staext) );    # New default May 2012
$stsext = 'STS' unless ( defined($stsext) );

# 04.01.2012 optional fourth parameters of prior rating file

( $toufile, $toustate, $toudate, $ratfile ) = @ARGV if @ARGV;
@ARGV     = ();
$toustate = uc($toustate) if defined($toustate);

@warnings = ();
$info     = '';

%touname = ();

print "$progname version $version ($probrule)\n";

### Print brief help at the command line
if ( defined($toufile) && ( $toufile =~ /help/i ) )
{

  print <<TELLHOW;
Syntax: $progname xxx.tou [state [date [priordat]]]
Updates Scrabble ratings.

xxx.tou  is a tournament file as produced by AUPAIR
state    is the state where tournament was held
date     is the date of the tournament YYYYMMDD
priordat is the filename of priordata eg 'RATING.DAT' or '09CAMB.RT2'

Wrong or missing parameters will be fixed by asking questions.

Prior ratings come from RATING.DAT or a recent RT2 file,
whichever is most recent.
TELLHOW

  exit;

}

# Give the opportunity to experiment with different parameters
# by overriding variables. New values are stored in 'parameters.pl'
# This probably won't work with the compiled version
# And perhaps this is just as well
@params = ();    # text within STA file
if ( -e 'parameters.pl' )
{
  do('parameters.pl');    # read the parameters
  open( PARAMTEXT, 'parameters.pl' )
    ;                     # save the text to display in the STA file
  @params = <PARAMTEXT>;
  unshift( @params, "WARNING: PARAMETERS HAVE BEEN MODIFIED\n" );
  close(PARAMTEXT);

}

# Can get state names from a file STATES.TXT
# Each line is one or more state names (3 letters maximum) separated by spaces
# The # marker can be used as a comment, anything after this is ignored
if ( -e 'STATES.TXT' )
{
  @states = ();
  open( STATESFILE, 'STATES.TXT' );
  while (<STATESFILE>)
  {
    chomp;
    $line = $_;
    $line =~ s/\#.+$//;    # get rid of comments
    foreach $st ( split( ' ', $line ) )
    {
      if ( length($st) < 4 ) { push( @states, uc($st) ) }
    }
  }
  close(STATESFILE);
}
else { @states = (qw/NSW ACT VIC SA QLD TAS WA OS/); }

# Ask about the TOU file if not given in @ARGV
# Forgive leaving off .tou
$toufile .= '.tou' if defined($toufile) && index( $toufile, '.' ) < 0;

# Present a list of recent TOU files if necessary
# 04.01.2012 change this to always read the list of TOU files
opendir( DIR, '.' );
@files = grep( /\.TOU$/i, readdir(DIR) );    # v 2.17 has the dot
closedir(DIR);
foreach $toufile (@files)
{
  if ( -f $toufile )
  {                                          # a file not a directory
    @bits           = split( '\.', $toufile );
    $toustub        = $bits[0];
    $done{$toufile} = -e "$toustub.$ratext" ? 'DONE' : 'NO ';

    @filedata = stat($toufile);
    $fdate{$toufile} = $filedata[9];    # reinstated v 2.21 as extra field

    #print "$toufile $fdate{$toufile}\n";
    open( TOUFILE, "$toufile" ) or die "Cannot open $toufile\n";
    $_ = <TOUFILE>;
    chomp;
    $line = $_;

    #*M15.01.2006 Baulkham Hills Kick-Off
    $title = substr( $line, 2, length($line) - 2 );

    if ( $title =~ /(\d{1,2})[\/\.](\d{1,2})[\/\.](\d*)\s*(.*)$/ )
    {
      $tyear            = $3 < 100 ? 2000 + $3 : $3;
      $tdate{$toufile}  = sprintf( "%04d%02d%02d", $tyear, $2, $1 );
      $tevent{$toufile} = $4;
    }
    else { $tdate{$toufile} = '00000000'; $tevent{$toufile} = $title; }

    close(TOUFILE);
  }    # if -f $toufile
}

if ( not defined($toufile) or not -e $toufile )
{

  @files
    = sort
  {
    $tdate{$b} == $tdate{$a}
      ? $fdate{$b} <=> $fdate{$b}
      : $tdate{$b} <=> $tdate{$a}
  } @files;
  @files = @files[ 0 .. 8 ] if @files > 9;

  if ( @files > 1 )
  {
    print "Recent TOU files\n\n";
    printf "   %-20s Done? %-35s %s\n", 'TOU file', 'event', 'date';
    printf
      "===========================================================================\n";
    for ( $i = 1; $i <= @files; $i++ )
    {
      printf "%2d %-20s %5s %-35s %-8s\n", $i, $files[ $i - 1 ],
        $done{ $files[ $i - 1 ] }, $tevent{ $files[ $i - 1 ] },
        $tdate{ $files[ $i - 1 ] };
    }
  }
  elsif ( @files == 0 ) { die "Cannot find any TOU files\n" }
  else                  { print "Only one TOU file found, so "; }

  if ( @files > 1 )
  {
    $gask = @files - 1;
    while ( ( $gask > 1 ) and ( $done{ $files[$gask] } eq '*' ) )
    {
      $gask--;
    }
    $gask++;
    do
    {
      print "Which file [$gask] ";
      $_ = <>;
      chomp;
      $ask = $_;
      $ask = $gask if $ask eq '';
    } until ( $ask <= @files );
  }

  $toufile = $files[ $ask - 1 ];
  print "using $toufile\n";
}

# open TOU file, at this stage just for the date
open( TOUFILE, "$toufile" ) or die "Cannot open $toufile\n";
$_ = <TOUFILE>;
chomp;
$line = $_;

#*M15.01.2006 Baulkham Hills Kick-Off
$title = substr( $line, 2, length($line) - 2 );

if ( $title =~ /(\d{1,2})[\/\.](\d{1,2})[\/\.](\d*)/ )
{
  $tyear     = $3 < 100 ? 2000 + $3 : $3;
  $titledate = sprintf( "%04d%02d%02d", $tyear, $2, $1 );

  #experiment
  #my $titledate = Time::Piece->strptime($str1, '%Y%m%d');
  $touyear = $tyear;

  #	$month = $2;
  #	$day = $1;
}

print "$toufile has title\n$title\n";
close(TOUFILE);

# Deal with the default state (may be second parameter of @ARGV)
#while ( not defined($toustate) or ( grep( $toustate eq $_, @states ) == 0 ) ) {
while ( not defined($toustate) )
{
  do
  {
    print "Default place for newbies eg where was it played?\n@states : ";
    $_ = <>;
    chomp;
    $toustate = uc($_);
  } until ( grep( $toustate eq $_, @states ) > 0 );
}

if ( not defined($toudate)
  or ( $toudate < 19910000 )
  or ( $toudate > 21000000 ) )
{
  print "Give the tournament date ";
  if ( defined($titledate) )
  {
    print "(default is $titledate) : ";
  }
  else { $titledate = '' }
  $_ = <>;
  chomp;
  $toudate = $_;
  $toudate = $titledate if $toudate eq '';
}

# deal with the file of prior ratings
@bits    = split( '\.', $toufile );
$toustub = $bits[0];

if ( not defined($ratfile) )
{
  opendir( DIR, '.' );
  @files = grep( /\.$ratext/i, readdir(DIR) );

  closedir(DIR);
  if ( -e 'RATING.DAT' )
  {
    unshift( @files, 'RATING.DAT' );
  }
  foreach $file (@files)
  {

    #@filedata = stat($file); $fdate{$file}=$filedata[9]}
    open( RATFILE, $file );
    $header          = <RATFILE>;                                    # header
    @bits            = split( ' ', $header );
    $event{$file}    = $bits[1];
    $lastdate{$file} = $bits[-1];
    $lastdate{$file} = '20000000' if $lastdate{$file} !~ /\d{8}$/;
    close RATFILE;
  }

  #@files = grep($toudate >= $lastdate{$_},@files);
  @files = grep( $_ !~ /$toustub/i, @files );
  @files = sort { $lastdate{$b} <=> $lastdate{$a} } @files;
  @files = @files[ 0 .. 8 ] if @files > 9;
  if ( @files > 1 )
  {
    print "Files with prior ratings\n\n";
    printf "  %-20s %-14s %s\n", 'Ratings file', 'last event', 'last date';
    printf "=================================================\n";
    for ( $i = 0; $i <= $#files; $i++ )
    {
      printf "%1d %-20s %-14s %-8s", $i + 1, $files[$i],
        $event{ $files[$i] }, $lastdate{ $files[$i] };

      if ( $toudate ge $lastdate{ $files[$i] } )
      {
        print "\n";
      }
      else { print " AFTER!\n" }
    }
  }
  elsif ( @files == 0 ) { die "Cannot find any ratings data files\n" }

  $ask = 1;
  if ( @files > 1 )
  {
    do
    {
      print "Which file [1] ";
      $_ = <>;
      chomp;
      $ask = $_;
      $ask = 1 if $ask eq '';
    } until ( $ask <= @files );
  }

  $ratfile = $files[ $ask - 1 ];
}

$ratfile = lc($ratfile);
unless ( -e $ratfile ) { print "Cannot find $ratfile"; <>; }
open( RATFILE, $ratfile ) or die "Cannot find $ratfile";

# newly introduced last item, last tou date
# NICKstateNAME                  06sydim.tou 20060129
# AFIS    VIC Andrew Fisher         315   1994   20060129
# NFER    VIC Naween Fernando       484   1969   20060129

$header = <RATFILE>;    # header
( $_, $ratevent, $lastdate ) = split( ' ', $header );
$ratevent =~ s/\..+//;
$ratevent =~ s/^.+\\//;
print "$ratfile\n$header\n";

if ( $toudate < $lastdate )
{
  print "Tournament date is $toudate ";
  print $toudate < $lastdate ? 'before' : 'same day as ';
  print "$lastdate from $ratfile\n";
  print "Is this okay? ";
  $ask = <>;
  chomp $ask;
  exit if ( uc($ask) ne 'Y' );
}

@oldlist = ();

while (<RATFILE>)
{
  chomp;
  $line = $_;
  next if length($line) < 40;
  $name = substr( $line, 9, 20 );    # eg Naween Fernando
  $name =~ s/\s+$//;

  #$name = &ucbits($name);                  # eg John Van Der Schoor
  $realname{ &squished($name) } = $name;    # eg JOHNVANDERSCHOOR, LAREINELANG
  $name      = &squished($name);
  $statemark = substr( $line, 5, 3 );       # eg VIC
  $statemark =~ s/\s+$//;
  $qname = $name . '^' . $statemark;
  $realname{$qname} = $realname{$name};       # allow lookup from squished to0
  $rat0{$qname}     = substr( $line, 35, 4 ); # eg 1853
  $oldrat{$qname}   = $rat0{$qname};
  $newrat{$qname}   = $rat0{$qname};

  $ratedgames{$qname} = substr( $line, 30, 4 );    # eg 595
  $ratedgames{$qname} =~ s/^\s+//;
  $lastplayed{$qname} = substr( $line, 40, 8 );

  #    $lastplayed{$qname1} = substr( $line, 40, 8 );
  #    print "qname $name lastplayed $lastplayed{$qname}\n";
  #    print "$line\n";

  $state{$name}  = $statemark;
  $games{$qname} = 0;
  push( @oldlist, $qname )    # all of them (no time filter yet)

}
close RATFILE;
$lastdate = '19900101' if $lastdate eq '';

#Stage 1 - get ratings of all players
# NICKstateNAME 06sydim1.tou
# NFER VIC Naween Fernando       595 1853 20060128
# EOKU NSW Edward Okulicz       1346 1797 20060128

# Stage 2   Check for unrated players
@newby = ();
&checkrat;
@qnewby = ();
readfixer();    # try moving it here

if ( scalar(@newby) > 0 )
{

  #readfixer();

  foreach $name (@newby)
  {

    if ( defined( $fixstate{$name} ) )
    {
      $st = $fixstate{$name};
    }

    else
    {
      $defaultstate = $toustate;

      # 04.01.2012 do not ask if found in the FROM file

      #printf "%-20s (%s) :", $touname{$name}, $defaultstate;
      $st = $defaultstate;
      unless ( defined($neverask) && $neverask > 0 )
      {    # For batch processing

        $errors = 99;
        while ( $errors > 0 )
        {
          printf "%-20s (%s) :", $realname{$name}, $defaultstate;

          $_ = <>;
          chomp;
          $st = uc($_) unless $_ eq '';
          if ( grep( $st eq $_, @states ) == 0 )
          {
            print "Unknown place $st for $name\n";
          }
          else { $errors = 0 }
        }

      }
      else
      {
        push( @warnings,
          sprintf( "%-20s (%s) NOVICE?", $realname{$name}, $defaultstate ) );
      }

    }

    stfixer();
    $qname = $name . '^' . $st;
    $state{$name} = $st;
    push( @qnewby, $qname );

    #  $lastplayed{$qname} = $toudate;
    $ratedgames{$qname} = 0;
    $rat0{$qname}       = 500;    # first guess, will solve by iteration
    $oldrank{$qname}    = 0;
    $oldsrank{$qname}   = 0;
    $boundary{$qname}   = 0;

  }
  unless ( defined($neverask) && $neverask == 1 )
  {
    writefixer("$toustub.csv");
  }
}

# Stage 3

$badboys  = 0;
@who      = ();
%forfeit  = ();
%walkover = ();
&parsetou;
if ( $badboys > 0 )
{
  print "Forfeits:\n";
  foreach $name ( keys %touname )
  {
    if ( defined( $forfeits{$name} ) )
    {
      print "$touname{$name} in game $forfeits{$name}\n";

  # push( @warnings, "$touname{$name} forfeited in game $forfeits{$name}\n" );
    }
  }
  print "\n";
}

@filterlist = ();
foreach $qname (@oldlist)
{
  ( $name, $st ) = split( '\^', $qname );
  if ( ( $games{$qname} > 0 )
    or ( $toudate - $lastplayed{$qname} < $currency * 10000 ) )
  {
    push( @filterlist, $qname );
  }
}
@filterlist
  = sort
{
  $rat0{$a} == $rat0{$b}
    ? $ratedgames{$b} <=> $ratedgames{$a}
    : $rat0{$b} <=> $rat0{$a}
} @filterlist;

#@filterlist = sort { $rat0{$b} <=> $rat0{$a} } @filterlist  ;

foreach $state (@states) { $counter{$state} = 0; }
$counter = 0;
for ( $i = 0; $i < scalar(@filterlist); $i++ )
{
  $qname = $filterlist[$i];
  ( $name, $st ) = split( '\^', $qname );
  unless ( $ratedgames{$qname} < $rankgames )
  {
    $counter++;
    $counter{$st}++;
  }
  $oldrank{$qname}  = $counter;
  $oldsrank{$qname} = $counter{$st};

}

# 19/09/2006 changed from sum of squares to max dev
$newstub = $toustub;

#print "$sections sections to rate \n";

for ( $secnum = 1; $secnum <= $sections; $secnum++ )
{
  do
  {
    $maxd = 0;

    &initnewbys($secnum);
    &inactive($secnum);
    &calcearned($secnum);

    # &feedback($secnum);
    &tally( $secnum, 0 );
  }

}

#@newlist = (@oldlist,@qnewby,@oldy);
@newlist = ( @filterlist, @qnewby );    #

#@newlist = sort { $newrat{$b} <=> $newrat{$a} } @newlist;
@newlist
  = sort
{
  $newrat{$a} == $newrat{$b}
    ? $ratedgames{$b} <=> $ratedgames{$a}
    : $newrat{$b} <=> $newrat{$a}
} @newlist;

foreach $state (@states) { $counter{$state} = 0; }
$counter = 0;
for ( $i = 0; $i < scalar(@newlist); $i++ )
{
  $qname = $newlist[$i];
  ( $name, $st ) = split( '\^', $qname );
  if ( $ratedgames{$qname} < $rankgames )
  {
    $newrank{$qname}  = $counter + 1;
    $newsrank{$qname} = $counter{$st} + 1;
  }
  else
  {
    $counter++;
    $counter{$st}++;
    $newrank{$qname}  = $counter;
    $newsrank{$qname} = $counter{$st};
  }

}
if (%forfeit)
{

  foreach $qname ( sort keys %forfeit )
  {
    ( $name, $st ) = split( '\^', $qname );
    $w = $touname{$name};
    printf "FORFEIT: %-20s in game %s\n", $w, $forfeit{$qname};

  }
}
if (%walkover)
{
  foreach $qname ( sort keys %walkover )
  {
    ( $name, $st ) = split( '\^', $qname );
    $w = $touname{$name};

    printf "WALKOVER: %-20s in game %s\n", $w, $walkover{$qname};

  }

}

# Stage 4.5 : Write the Rat difference and wins file
#$s = $probrule eq 'logit' ? "$probrule$logitk" : "$probrule$lineark";
#$rule = "+--------------------------+-----------+----------------+\n";
#open( STAFILE, ">>batchratlog.$staext" );
##print STAFILE <<HEADER;
##Rating stats for $title ($toustate) generated by $progname $version ($s)
##Prior data from $ratfile after $ratevent ($lastdate)
##@params
##+--------------------------+-----------+----------------+
##| State     Name           |   % Wins  | Rating Points  |
##|                          | Exp  Act  | Old Change New |
##HEADER
## | VIC Naween Fernando      |    0    0 |   0    0| 12.3 13.0 | 1841  +12 1853 |
#$n_novices  = 0;
#$n_forfeits = 0;
#$n_provs    = 0;

for ( $secnum = 1; $secnum <= $sections; $secnum++ )
{
  printf STAFILE "+Section %-18s", $secname[$secnum];

  #print  STAFILE "+           +         +           +               +\n";
  printf STAFILE "+%3d games  + Old  Diff  Opp +\n", $maxgames[$secnum];
  print STAFILE $rule;
  $gcap = $maxgames[$secnum];

  foreach $player ( sort byplacing ( 1 .. $secsize[$secnum] ) )
  {
    $qname = $who[$secnum][$player];

    ( $name, $st ) = split( '\^', $qname );
    if ( $name =~ /^. Bye$/ )
    {
      push( @warnings, "$name treated as a bye" );

    }
    elsif ( $games{$qname} == 0 )
    {
      push( @warnings, "$name played no games!" );

    }
    else
    {
      if ( $games{$qname} > 8 )
      {
        if ( $games{$qname} < $gcap )
        {
          print STAFILE "+--------------------------+-";
          printf STAFILE "%2s games -+----------------+\n", $games{$qname};
          $gcap = $games{$qname};
        }

        if ( $ratedgames{$qname} == 0 ) { $marker = '|*'; $n_novices++ }
        elsif ( defined( $forfeits{$name} ) )
        {
          $marker = '|x';
          $n_forfeits++;
        }
        elsif ( ( $ratedgames{$qname} > 0 )
          and ( $ratedgames{$qname} < $proviso ) )
        {
          $marker = '|&';
          $n_provs++;
        }
        else { $marker = '| ' }

        #     print STAFILE ($ratedgames{$name1}==0) ? '|*' : '| ';

        $rmark = $ratedgames{$qname} < $rankgames ? '.' : ' ';

        printf STAFILE "%2s%-3s %-20s |", $marker, $st, $realname{$name};

        # expected games
        if    ( $ratedgames{$qname} < $proviso ) { print STAFILE "     " }
        elsif ( $ratedgames{$qname} == 0 )       { print STAFILE "     " }
        else
        {
          printf STAFILE "%5.1f", $expected{$qname} / $games{$qname} * 100;
        }

        printf STAFILE "%5.1f |", $ratedgames{$qname} == 0
          && $wins{$qname} < 1 ? 0 : $wins{$qname} / $games{$qname} * 100;

        # end expected wins column
        if ( $ratedgames{$qname} == 0 )
        {
          #print for newbies
          print STAFILE ' ' x 11;
        }
        elsif ( $ratedgames{$qname} < $proviso )
        {
          printf STAFILE "(%4d) %+4d", $rat0{$qname}, $rat0{$qname}
            - $sumopprat{$qname1} / ( $games{$qname} - $rawopps{$qname} );
        }
        elsif ( $boundary{$qname} != 0 )
        {
       #                printf STAFILE " %4d     ", $sumopprat/$games{$qname};
        }

        #otherwise non-provisional
        else
        {
# printf STAFILE " %4d  %+4d", $rat0{$qname}, $rat0{$qname}-$sumopprat/($games{$qname});
          printf STAFILE " %4d  %+4d", $rat0{$qname}, $rat0{$qname};
        }

        #print rightmost column
        if ( $ratedgames{$qname} + $games{$qname} < $proviso )
        {
#printf STAFILE " %4d |\n", $hisrat{$qname1}-$sumopprat/($games{$qname}-$rawopps{$qname});
          printf STAFILE " %4d |\n", $hisrat{$qname1};

        }
        else
        {
#               printf STAFILE " %4d |\n", $rat0{$qname1}-$sumopprat/($games{$qname}-$rawopps{$qname});
          printf STAFILE " %4d |\n", $rat0{$qname1};

        }

      }
    }
  }    # if not a bye
  print STAFILE "$rule";

}

close STAFILE;

# Stage 5 : Write the STA file
$s = $probrule eq 'logit' ? "$probrule$logitk" : "$probrule$lineark";
$rule
  = "+--------------------------+-----------+---------+-----------+----------------+\n";
open( STAFILE, ">$newstub.$staext" );
print STAFILE <<HEADER;
Stats for $title ($toustate) generated by $progname $version ($s)
Prior data from $ratfile after $ratevent ($lastdate)
Rankings are amongst players active in the last $currency years who have played at least $rankgames games.
@params
+--------------------------+-----------+---------+-----------+----------------+
| State     Name           | World     | Nation  |   Wins    | Rating Points  |
|                          | Old  New  | Old New | Exp  Act  | Old Change New |
HEADER

# This is what we intend to print
# +--------------------------+-----------+---------+-----------+----------------+
# | VIC Andrew Fisher        |    0    0 |   0    0| 11.8 16.0 | 1836  +67 1903 |
# | VIC David Eldar          |    0    0 |   0    0| 11.9 14.0 | 1825  +33 1858 |
# | VIC Naween Fernando      |    0    0 |   0    0| 12.3 13.0 | 1841  +12 1853 |
$n_novices  = 0;
$n_forfeits = 0;
$n_provs    = 0;

for ( $secnum = 1; $secnum <= $sections; $secnum++ )
{
  printf STAFILE "+Section %-18s", $secname[$secnum];

  #print  STAFILE "+           +         +           +               +\n";
  printf STAFILE "+           +         +%3d games  +                +\n",
    $maxgames[$secnum];
  print STAFILE $rule;
  $gcap = $maxgames[$secnum];

  foreach $player ( sort byplacing ( 1 .. $secsize[$secnum] ) )
  {
    $qname = $who[$secnum][$player];

    ( $name, $st ) = split( '\^', $qname );
    if ( $name =~ /^. Bye$/ )
    {
      push( @warnings, "$name treated as a bye" );

    }
    elsif ( $games{$qname} == 0 )
    {
      push( @warnings, "$name played no games!" );

    }
    else
    {
      if ( $games{$qname} < $gcap )
      {
        print STAFILE "+--------------------------+-----------+---------+-";
        printf STAFILE "%2s games -+----------------+\n", $games{$qname};
        $gcap = $games{$qname};
      }

      if ( $ratedgames{$qname} == 0 ) { $marker = '|*'; $n_novices++ }
      elsif ( defined( $forfeits{$name} ) )
      {
        $marker = '|x';
        $n_forfeits++;
      }
      elsif ( ( $ratedgames{$qname} > 0 )
        and ( $ratedgames{$qname} < $proviso ) )
      {
        $marker = '|&';
        $n_provs++;
      }
      else { $marker = '| ' }

      #     print STAFILE ($ratedgames{$name1}==0) ? '|*' : '| ';

      $rmark = $ratedgames{$qname} < $rankgames ? '.' : ' ';

      printf STAFILE "%2s%-3s %-20s |", $marker, $st, $realname{$name};

      # national ranks
      if   ( $rmark eq '.' ) { printf STAFILE "     " }
      else                   { printf STAFILE "  %3d ", $oldrank{$qname} }

      if ( $rmark eq '.' )
      {
        printf STAFILE "%6s|", '(' . $newrank{$qname} . ')';
      }
      else { printf STAFILE "%4d |", $newrank{$qname} }

      # state ranks
      if   ( $rmark eq '.' ) { printf STAFILE "    " }
      else                   { printf STAFILE "%4d ", $oldsrank{$qname} }

      if ( $rmark eq '.' )
      {
        printf STAFILE "%5s|", '(' . $newsrank{$qname} . ')';
      }
      else { printf STAFILE "%3d |", $newsrank{$qname} }

      # expected games
      if    ( $ratedgames{$qname} < $proviso ) { print STAFILE "     " }
      elsif ( $ratedgames{$qname} == 0 )       { print STAFILE "     " }
      else { printf STAFILE "%5.1f", $expected{$qname}; }

      printf STAFILE "%5.1f |",
        $ratedgames{$qname} == 0 && $wins{$qname} < 1 ? 0 : $wins{$qname};

      if ( $ratedgames{$qname} == 0 )
      {
        print STAFILE ' ' x 10;
      }
      elsif ( $ratedgames{$qname} < $proviso )
      {
        printf STAFILE "(%4d)    ", $rat0{$qname};
      }
      elsif ( $boundary{$qname} != 0 )
      {
        printf STAFILE " %4d     ", $rat0{$qname};
      }
      else
      {
        printf STAFILE " %4d %+4d", $rat0{$qname},
          $newrat{$qname} - $rat0{$qname};
      }

      if ( $ratedgames{$qname} + $games{$qname} < $proviso )
      {
        printf STAFILE "(%4d)|\n", $newrat{$qname};
      }
      else
      {
        printf STAFILE " %4d |\n", $newrat{$qname};
      }

    }
  }    # if not a bye
  print STAFILE "$rule";

}

#printf STAFILE "Games in this tourney = %5d\n",$maxgames;
print STAFILE "\n\nNotes:\nTournament placings by wins and ";
print STAFILE "aggregate.\n" if $rankmethod eq 'A';
print STAFILE "spread.\n\n"  if $rankmethod eq 'M';

#handle inactive and rapidly improving players
for ( $secnum = 1; $secnum <= $sections; $secnum++ )
{

  foreach $player ( sort byplacing ( 1 .. $secsize[$secnum] ) )
  {
    $qname = $who[$secnum][$player];
    if ( $games{$qname} > $proviso )
    {
      if ( $toudate - $lastplayed{$qname} > $currency * 10000 )
      {
        print STAFILE "$qname is inactive, last played $lastplayed{$qname}\n";
      }
    }
    if ( $earned{$qname} > 20 * $games{$qname} )
    {
      print STAFILE "$qname rating change is $earned{$qname}";
    }
  }
}    # end print for inactivity

print STAFILE "* denotes a previously unrated player\n" if $n_novices > 0;
print STAFILE "x denotes a player who forfeited\n"      if $n_forfeits > 0;
print STAFILE "& denotes a provisional player\n"        if $n_provs > 0;

for ( $secnum = 1; $secnum <= $sections; $secnum++ )
{
  print STAFILE
    "Because $secname[$secnum] section had $maxgames[$secnum]>$longlimit games, ratings were done in $runs[$secnum] passes.\n"
    if $runs[$secnum] > 1;
}

# Print warnings about players who played many unrated players
for ( $secnum = 1; $secnum <= $sections; $secnum++ )
{
  foreach $player ( sort byplacing ( 1 .. $secsize[$secnum] ) )
  {
    $qname = $who[$secnum][$player];
    if ( $qname !~ /^. Bye\^/ )
    {
      if ( $games{$qname} > 0 )
      {
        ( $name, $st ) = split( '\^', $qname );

#    print "WARNING $name played $rawopps{$qname}/$games{$qname} unrated players.\n" if $rawopps{$qname} >0;
        $rawperc
          = sprintf( "%3.0f", $rawopps{$qname} * 100 / $games{$qname} );
        if ( $rawperc > 50 )
        {
          print STAFILE
            "$touname{$name} ($rat0{$qname}) played $rawopps{$qname}/$games{$qname}=$rawperc\% unrated players.\n";
          if ( $games{$qname} > $proviso )
          {
            if ( $earned{$qname} > 5 * $games{$qname} )
            {
              print STAFILE
                "$touname{$name} got accelerated by $bonus points \n";
            }
          }

# push(@warnings,"$touname{$name} ($rat0{$qname}) played $rawopps{$qname}/$games{$qname}=$rawperc\% unrated players.\n");

        }
      }
      else
      {
        print STAFILE "$touname{$name} played no bloody games at all! WTF!\n";
        push( @warnings,
          "$touname{$name} played no bloody games at all! WTF!" );
      }
    }
  }
}

close STAFILE;

open( STSFILE, ">$newstub.$stsext" )
  ;    # New comma delimited version for easy Aarchive programming
for ( $secnum = 1; $secnum <= $sections; $secnum++ )
{
  foreach $player ( sort { $who[$secnum][$a] cmp $who[$secnum][$b] }
    ( 1 .. $secsize[$secnum] ) )
  {
    $qname = $who[$secnum][$player];
    ( $name, $st ) = split( '\^', $qname );
    if ( $name =~ /^. Bye$/ )
    {

    }
    elsif ( $games{$qname} == 0 )
    {

    }
    else
    {
      printf STSFILE "%s,%s,%s,", $secname[$secnum], $st,
        $realname{$name};    #Identity
      printf STSFILE "%d,%5.3f,%4.1f,", $games{$qname}, $expected{$qname},
        $wins{$qname};       #tournament result
      printf STSFILE "%d,%+d,", $ratedgames{$qname},
        $games{$qname};      # games original, delta
      printf STSFILE "%4d,%4d,", $rat0{$qname},     $newrat{$qname};
      printf STSFILE "%d,%d,",   $oldrank{$qname},  $newrank{$qname};
      printf STSFILE "%d,%d\n",  $oldsrank{$qname}, $newsrank{$qname};
    }
  }
}

close STSFILE;

# Stage 4 : Create new RATING.DAT file
# NICKstateNAME                   060107ja.tou
# EOKU NSW Edward Okulicz       1321 1853 20051203
# NFER VIC Naween Fernando       564 1841 20051228
# DELD VIC David Eldar           389 1836 20051228

#Newlist must be redone need to put back those set aside earlier
$report = $toufile;           # eg blah.tou;
$report =~ s/\..+$/\.txt/;    #text file follows the name of tou file ;
%p_tell = ();

#open( NICEFILE, ">$report" ) or print "Cannot write to $report\n";
open( NICEFILE, ">$report" ) or die "Cannot write to $report\n";
print NICEFILE "Results and ratings: $title\n";
print NICEFILE "following $ratevent on $lastdate\n";
for ( $secnum = 1; $secnum <= $sections; $secnum++ )
{

  print NICEFILE "$secname[$secnum]\n";
  printf NICEFILE "\n%8d games\n", $maxgames[$secnum];
  $gcap = $maxgames[$secnum];
  printf NICEFILE "%3s %4s %5s", '', 'W', $rankmethod;
  printf NICEFILE "%-26s %s\n", '', 'Old  Chg  New';
  $rank = 0;

  # sort players by placing
  foreach $player ( sort byplacing ( 1 .. $secsize[$secnum] ) )
  {
    $qname = $who[$secnum][$player];
    ( $name, $st ) = split( '\^', $qname );

    if ( $name !~ /^. Bye$/ )
    {
      #if you are a bye, your rank moves up by 1
      $rank++;
      $newtotgames{$qname} = $ratedgames{$qname} + $games{$qname};

      if ( $games{$qname} < $gcap )
      {
        printf NICEFILE "\n%8d games\n", $games{$qname};
        $gcap = $games{$qname};
        $rank = 1;
      }

      printf NICEFILE "%3d %4g %+5d", $rank, $wins{$qname}, $totscore{$qname};
      print NICEFILE $ratedgames{$qname} == 0 ? '*'
        : $ratedgames{$qname} < $proviso      ? '&'
        :                                       ' ';

      printf NICEFILE "%3s %-20s", $state{$name}, $realname{$name};
      if ( $ratedgames{$qname} == 0 )
      {
        print NICEFILE "          ", '';
        $p_tell{$qname} = "$realname{$name} was previously unrated";
      }
      elsif ( $ratedgames{$qname} < $proviso )
      {
        printf NICEFILE "(%4d)%4s", $rat0{$qname}, '';
        $p_tell{$qname} = "$realname{$name} was previously provisional";
      }

      else
      {
        printf NICEFILE " %4d %+4d", $rat0{$qname},
          $newrat{$qname} - $rat0{$qname};
      }

      if ( $newtotgames{$qname} < $proviso )
      {
        printf NICEFILE "(%4d)\n", $newrat{$qname};
        if ( defined( $p_tell{$qname} ) )
        {
          if ( $p_tell{$qname} =~ /provisional/ )
          {
            $p_tell{$qname}
              = "$realname{$name} is still provisional ($newtotgames{$qname} games)";
          }
        }

      }
      else
      {
        printf NICEFILE " %4d\n", $newrat{$qname};
        if ( defined( $p_tell{$qname} ) )
        {
          $p_tell{$qname}
            = "$realname{$name} is no longer provisional ($newtotgames{$qname} games)";
        }

      }
    }    # if !~ /Bye$/
  }    # foreach $player

  print NICEFILE "\n";

  printf NICEFILE "\nHigh game: %s %s \n", $whohighgame[$secnum],
    $highgame[$secnum] % 1000;
  print NICEFILE "High word: $highword[$secnum]\n"
    unless $highword[$secnum] =~ /\s+0\s+/;
  print NICEFILE "\n\n";
}

#Explain about novices and provisional
@x = keys %p_tell;
if ( @x > 0 )
{
  foreach $qname ( sort { $newtotgames{$a} <=> $newtotgames{$b} } @x )
  {
    print NICEFILE "$p_tell{$qname}\n";

  }
}
close NICEFILE;

@newlist
  = sort
{
  $newrat{$a} == $newrat{$b}
    ? $ratedgames{$b} <=> $ratedgames{$a}
    : $newrat{$b} <=> $newrat{$a}
} ( @oldlist, @qnewby );

open( NEWRATFILE, ">$newstub.$ratext" );
printf NEWRATFILE "%-32s%s %s\n", 'NICKstateNAME', lc($toufile), $toudate;
for ( $i = 0; $i < scalar(@newlist); $i++ )
{
  $qname = $newlist[$i];

  # This should not happen I hope
  if ( $qname eq $newlist[ $i - 1 ] )
  {
    print "Duplicated entry for $qname!\n";
    <>;
  }

  ( $name, $st ) = split( '\^', $qname );
  if ( $name =~ /\w/ )
  {    # avoid spurious zeros at end
    printf NEWRATFILE "%4s %-4s%-20s", &nickname( $realname{$name} ), $st,
      $realname{$name};

    #print "$name $games{$qname}"; <>;
    if ( $games{$qname} > 0 )
    {
      printf NEWRATFILE "%5d%5d%9d\n", $ratedgames{$qname} + $games{$qname},
        $newrat{$qname}, $toudate;
    }
    else
    {
      printf NEWRATFILE "%5d%5d%9d\n", $ratedgames{$qname}, $rat0{$qname},
        $lastplayed{$qname};
    }
  }
}    # for loop
print "\n";
close(NEWRATFILE);

print "\nNew rating file created : $newstub.$ratext\n";
print "Stats report created    : $newstub.$staext\n";
print "Archive report created  : $newstub.$stsext\n";
print "Combined report         : $newstub.txt\n";

#print "From where file         : F$newstub.csv\n" if (@newby);
#print "Spreadsheet check       : check.csv\n" if $write_to_CSV;
#print "\nPress ENTER to conclude";
#<>;

sub byplacing
{
  my $qname1 = $who[$secnum][$b];
  my $qname2 = $who[$secnum][$a];
  if ( $games{$qname1} != $games{$qname2} )
  {
    $games{$qname1} <=> $games{$qname2};
  }
  elsif ( $wins{$qname1} != $wins{$qname2} )
  {
    $wins{$qname1} <=> $wins{$qname2};
  }
  else { $totscore{$qname1} <=> $totscore{$qname2} }

}

sub checkrat
{
  my ( $line, $name );
  open( TOUFILE, "$toufile" ) or die "Cannot open $toufile\n";
  $_ = <TOUFILE>;
  chomp;
  $line = $_;

  $rankmethod = substr( $line, 1, 1 );    # should be A or M
  while (<TOUFILE>)
  {
    chomp;
    $line = $_;
    if ( substr( $line, 0, 1 ) eq '*' )
    {
      last if $line eq '*** END OF FILE ***';
      <TOUFILE>;                          #highword;
    }
    else
    {

      $name = substr( $line, 0, 20 );
      $name =~ s/@.+$//;                  # get rid of @R, @12
      $name =~ s/\(.+$//;                 # get rid of (N) etc
      $name =~ s/\s+$//;                  # get rid of trailing spaces
      $touname{ &squished($name) } = $name;
      $name = &squished($name);
      unless ( defined( $realname{$name} ) )
      {
        $realname{$name} = $touname{$name};
      }

      #$qname=$name.'^'.$toustate;     ## NO not right
      # now check for ambiguous names and unrated players

      @result = grep( $_ =~ /^$name\^[A-Z]*/, keys %rat0 );
      $n      = @result;
      if ( ( $n == 0 ) and ( $name !~ /^. Bye$/ ) )
      {    # n=0 no prior rating from RATING.DAT

        push( @newby, $name );

      }
      elsif ( $n == 1 )
      {    # May be Edward Okulicz^NSW playing in Victoria!
        $qname = $result[0];
      }
    }

  }    # while TOUFILE
  close TOUFILE;

}    # sub checkrat

# subroutine creates a number indexed array of players, opponents etc
# naughty because it uses and creates global variables
sub parsetou
{
  my ( $player, $secnum, $line, $name );
  open( TOUFILE, "$toufile" ) or die "Cannot open $toufile\n";
  $_ = <TOUFILE>;
  chomp;
  $line = $_;

  $rankmethod = substr( $line, 1, 1 );    # should be A or M
  $player     = 0;
  $secnum     = 0;

  while (<TOUFILE>)
  {
    chomp;
    $line = $_;
    if ( substr( $line, 0, 1 ) eq '*' )
    {
      $secsize[$secnum]     = $player;
      $whohighgame[$secnum] = join( ',', @smarties ) if $secnum > 0;

      last if $line eq '*** END OF FILE ***';
      $secnum++;
      $secname[$secnum] = substr( $line, 1, 20 );

      # print "SECTION $secnum is $secname[$secnum]\n"; <>; # debug
      $highgame[$secnum] = 0;
      @smarties          = ();
      $h                 = <TOUFILE>;
      chomp;
      $h =~ s/\s+/ /g;
      $highword[$secnum] = $h;

      # print "SECTION $secnum is $secname[$secnum]\n"; <>; # debug

      $player = 0;
    }
    else
    {

      $player++;
      $name = substr( $line, 0, 20 );

      $name =~ s/@.+$//;     # get rid of @R, @12
      $name =~ s/\(.+$//;    # get rid of (N) etc
      $name =~ s/\s+$//;     # get rid of trailing spaces
      $touname{ &squished($name) } = $name;
      $name = &squished($name);

      if ( $name =~ /^. Bye$/ )
      {                      # n=0 no prior rating from RATING.DAT
        $qname                 = $name . "^OS";
        $rat0{$qname}          = 0;
        $realname{$name}       = $name;           # ??
        $games{$qname}         = 0;
        $wins{$qname}          = 0;
        $who[$secnum][$player] = $qname;
      }

      if ( $name !~ /^. Bye$/ )
      {
        @result = grep( $_ =~ /^$name\^[A-Z]*/, keys %rat0 );
        $n = @result;    # number of players named eg Joy Smith in RATING.DAT

        if ( $n == 0 )
        {                # n=0 no prior rating from RATING.DAT
          print "ERROR: No prior rating for $name";
          die;
        }
        elsif ( $n == 1 )
        {                # May be Edward Okulicz^NSW playing in Victoria!
          $qname = $result[0];
        }
        elsif ( $n > 1 )
        {                # n>1 is ambiguous
          $ask = 'n';
          while ( $ask ne 'Y' )
          {
            print "Which of these $n is $name (type Y)?\n";
            foreach $joy (@result)
            {
              ( $name, $st ) = split( '\^', $joy );
              print "$touname{$name} from $st? ";
              $_ = <>;
              chomp;
              $ask   = uc($_);
              $qname = $joy;
              last if $ask eq 'Y';
            }

          }    # if $n>1
          $who[$secnum][$player] = $qname;
          undef( $forfeits{$name} );
          $newrat{$qname} = $rat0{$qname};
          $games{$qname}  = 0;

          $boundary{$qname} = 0;
          $roof{$qname}     = 0;

          # print "$qname\n"; #debug

          substr( $line, 0, 20 ) = ' ' x 20;
          $long = 0;
          if ( $line =~ /[a-z]/ )
          {
            print "$line\n";
            $long = 1;
          }

        }    # if $n>1
        $who[$secnum][$player] = $qname;
        undef( $forfeits{$name} );
        $newrat{$qname} = $rat0{$qname};
        $games{$qname}  = 0;
        $wins{$qname}   = 0;

        $boundary{$qname} = 0;
        $roof{$qname}     = 0;

        # print "$qname\n"; #debug

        substr( $line, 0, 21 ) = ' ' x 21;    # Preedee

        @data = split( ' ', $line );

        $game = 0;
        while ( scalar(@data) )
        {

          $score  = shift(@data);
          $oppnum = shift(@data);

          if ( $score > 0 )
          {    # ver 2.19 ignore prospective games }
            $win = 0.5 * int( $score / 1000 );    # should be 0, 0.5 or 1
            $game++;
            $score[$secnum][$game][$player] = $score % 1000;

            if ( $score > $highgame[$secnum] )
            {
              $highgame[$secnum] = $score;
              @smarties = ( $realname{$name} );

            }
            elsif ( $score == $highgame[$secnum] )
            {
              push( @smarties, $realname{$name} );
            }

            if ( $score == 002 )
            {    # code for forfeited game
              $forfeits{$name} .= ' ' . $game;
              $badboys++;
            }

            $hisopp[$secnum][$player][$game] = $oppnum;
            $hiswin[$secnum][$player][$game] = $win;
            if ( $oppnum != $player ) { $wins{$qname} += $win; }
            if ( $score < $warntrigger && $score > 9 )
            {
              push( @warnings,
                "Piddly score of $score for $realname{$name} in round $game"
              );

            }

          }
          else
          {
            push( @warnings,
              "Zero score for $realname{$name} in round $game" );
          }
          $hisgames[$secnum][$player] = $game;
          $games{$qname} = $game;
        }

      }    #if not A Bye
    }

  }    # while TOUFILE
  close TOUFILE;
  $sections = $secnum;
  if ( $rankmethod eq 'M' )
  {
    foreach $secnum ( 1 .. $sections )
    {
      foreach $player ( 1 .. $secsize[$secnum] )
      {
        $qname = $who[$secnum][$player];
        $totscore{$qname} = 0;
        foreach $game ( 1 .. $hisgames[$secnum][$player] )
        {
          $opp = 0 + $hisopp[$secnum][$player][$game];
          $totscore{$qname}
            += $score[$secnum][$game][$player] - $score[$secnum][$game][$opp];
        }

      }
    }
  }
}    # sub parsetou

sub readfixer
{
  my $filename = "F$toustub.csv";
  my @bits;
  unless ( -e $filename )
  {
    $filename = 'PLAYERS.csv';
  }
  if ( -e $filename )
  {
    open( FIXER, $filename );
    while (<FIXER>)
    {
      chomp;
      if (/,/)
      {
        @bits = split( ',', $_ );
        $fixstate{ squished( $bits[0] ) } = $bits[1];
      }
    }
    close FIXER;
  }
}

sub writefixer
{
  my ($fname) = @_;
  unless ( -e 'PLAYERS.csv' )
  {
    my $bettername;
    open( FIXER, ">$fname" );
    foreach my $name (@newby)
    {
      $bettername = $realname{$name};
      print FIXER "$bettername,$state{$name}\n";
    }
    close FIXER;
  }
}

sub initnewbys
{
  my ($secnum) = @_;

  #    print " secnum is $secnum\n";
  for ( $player = 1; $player <= $secsize[$secnum]; $player++ )
  {

    $qname1   = $who[$secnum][$player];
    $datediff = $toudate - $lastplayed{$qname1};

    if ( $ratedgames{$qname1} == 0 or $datediff > 50000 )
    {
      $oldrat{$qname1}  = $oldrat{$qname};
      $sumopprat        = 0;
      $rawopps{$qname1} = 0;

      #	        print "Checking new player $qname1 ($rat0{$qname1})\n";

      #		$games{$qname1} = 0;
      my $totalGames = 0;
      for ( $game = 1; $game <= $hisgames[$secnum][$player]; $game++ )
      {
        $rival  = $hisopp[$secnum][$player][$game];
        $qname2 = $who[$secnum][$rival];
        unless ( defined($qname2) )
        {
          print "Game $game: $who[$secnum][$player] opponent no $rival\n";

          #<>;
        }
        if ( ( $rival == $player ) or $qname2 =~ /^. Bye\^/ )
        {

          #printf "$qname1 played $qname2\n";
          $game-- or print "Stuck";
        }

        else
        {
          #add up number of games, averages opponents' ratings
          $totalGames++;

          #                        $games{$qname1}++;
          #			print "$qname1 played $qname2 rated $rat0{$qname2}\n";
          #			print "		$qname2 has played $ratedgames{$qname2} games\n";
          if ( $ratedgames{$qname2} == 0 )
          {
            $rawopps{$qname1}++;
          }
          else
          {
            $sumopprat += $rat0{$qname2};
          }

        }    # if $rival!= $player
      }    # for $game

      #			$ratedopps = $games{$qname1} - $rawopps{$qname1};
      #			if ($ratedopps/$games{$qname1} < 0.5){
      $ratedopps = $totalGames - $rawopps{$qname1};
      if ( $ratedopps / $totalGames < 0.5 )
      {
        #TRIALLING: Benefit of Doubt for players with many unrated opps
        #$sumopprat += 10*(1-$ratedopps/$games{$qname1});
      }

#print "DEBUG $qname1 played $games{$qname1} games with $ratedopps rated, $rawopps{$qname1} unrated\n";

      if ( $ratedopps > 0 )
      {
        $rat0{$qname1} = int( $sumopprat / $ratedopps );

#				print "$qname1 given $rat0{$qname1} to start. \n";
#				print "sumopprat $sumopprat; ratedopps $ratedopps; rawopps $rawopps{$qname1}\n";
        $perfchange
          = @rmultiplier
          * $totalGames
          * ( $wins{$qname1} / $totalGames - 0.5 );
        $perfchange
          = @rmultiplier
          * $games{$qname1}
          * ( $wins{$qname1} / $games{$qname1} - 0.5 );

        #Additional penalty for players winning below one-third of games

        #			print "$qname1 won $wins{$qname1} in $games{$qname1}\n";
        #			if ($wins{$qname1} / $games{$qname1} < 1/3){
        if ( $wins{$qname1} / $totalGames < 1 / 3 )
        {
   #gradual increase in multiplier for players winning less than 1/3 of games;
          $perfchange
            *= int( ( 1 + 3 / 3 - 3 * $wins{$qname1} / $totalGames ) );
          if ( $wins{$qname1} / $totalGames < 0.2 )
          {
            $perfchange *= 1.75 + 0.2 - $wins{$qname1} / $totalGames;
          }

 #				 print "$qname1 's perfchange is $perfchange, newrat $rat0{$qname1} \n";
        }

        #			print " DEBUG $qname1 avg $rat0{$qname1} adj $perfchange";
        #				print "Adjusting rating by $perfchange\n";
        $rat0{$qname1} += int($perfchange);

        if ( $rat0{$qname1} > 1800 )
        {
          if ( $rat0{$qname1} > 2000 )
          {
            #reduce overrating due to crossing boundaries
            $rat0{$qname1} = 2000 + ( $rat0{$qname1} - 2000 ) * 0.625;
          }
          $rat0{$qname1} = 1800 + ( $rat0{$qname1} - 1800 ) * 0.8;

        }

        if ( $rat0{$qname1} < 1000 )
        {
          $rat0{$qname1} = 1000 + ( $rat0{$qname1} - 1000 ) * 0.8;
        }
      }
      else { $rat0{$qname1} = 1000; }    # all unrated opps; guess 1200
      $rat0{$qname1} = int( $rat0{$qname1} );
      print "$qname1 initialized to $rat0{$qname1};\n";

    }    # if unrated
  }    # for $player

}    # end initnewbys

sub inactive
{

  my ($secnum) = @_;

  for ( $player = 1; $player <= $secsize[$secnum]; $player++ )
  {

    $qname1 = $who[$secnum][$player];

#    print "Running sub inactive for $qname1, last played $lastplayed{$qname1}\n";
    if ( ( $toudate - $lastplayed{$qname1} > $currency * 10000 )
      & $ratedgames{$qname1} > 0 )
    {

      print "$qname1 is inactive, $lastplayed{$qname1}\n";
      $stlastplayed{$qname1} = $lastplayed{$qname1};

    }    # for player

  }    #if inactive

  #end inactivity
}

sub calcearned
{
  my ($secnum) = @_;

  $maxgames[$secnum] = 0;
  for ( $player = 1; $player <= $secsize[$secnum]; $player++ )
  {
    $maxgames[$secnum] = $hisgames[$secnum][$player]
      if $hisgames[$secnum][$player] > $maxgames[$secnum];
    $qname1 = $who[$secnum][$player];

    #	print "Calculating rating change for $qname1\n\n";

    $hisrat{$qname1}  = $rat0{$qname1};
    $earned2{$qname1} = 0;                # for multipass in long tournaments
    $mix{$qname1}     = '';
  }

  $runs[$secnum] = int( ( $maxgames[$secnum] + $longlimit - 1 ) / $longlimit )
    ;    # eg longlimit =10, games=21..29, runs=3

  foreach $run ( 1 .. $runs[$secnum] )
  {
    for ( $player = 1; $player <= $secsize[$secnum]; $player++ )
    {
      $qname1 = $who[$secnum][$player];

      if ( $qname1 !~ /^. Bye\^/ )
      {
        ( $name, $st ) = split( '\^', $qname1 );

        #                $wins{$qname1}     = 0;
        #                $wins{$qname1}     = 0;
        $games{$qname1}    = 0;
        $expected{$qname1} = 0;
        $earned{$qname1}   = 0;
        $sumopprat         = 0;
        $rawopps{$qname1}  = 0;
        @opprats           = ();

        for ( $game = 1; $game <= $hisgames[$secnum][$player]; $game++ )
        {
          $rival  = $hisopp[$secnum][$player][$game];
          $qname2 = $who[$secnum][$rival];
          unless ( defined($qname2) )
          {
            print "Game $game: $who[$secnum][$player] opponent no $rival\n";

            #<>;
          }
          if ( ( $rival == $player ) or $qname2 =~ /^. Bye\^/ )
          {

            # print "$qname1 played $qname2\n";
          }

          else
          {
            #add up number of games, averages opponents' ratings
            $games{$qname1}++;
            $opporat = $hisrat{$qname2};
            push( @opprats, $opporat );
            $rawopps{$qname1}++ if $ratedgames{$qname2} == 0;
            $sumopprat += $opporat;
            $exp = &$probrule( $hisrat{$qname1} - $opporat );

            #                        $act = $hiswin[$secnum][$player][$game];
            $expected{$qname1} += $exp;

            #                        $wins{$qname1}     += $act;

          }    # if $rival!= $player
        }    # for $game

        die "$qname1 has no games" if $games{$qname1} == 0;

        $roof{$qname1} = $sumopprat / $games{$qname1} + $roofcap;

#  if ( $ratedgames{$qname1} == 0 ) { $opporats{$qname1} = join( '+', @opprats ) }
# calculation of ratings for established players
        $gap = $wins{$qname1} - $expected{$qname1};
        $earned{$qname1} = rmult( $hisrat{$qname1}, $gap, $runs[$secnum] );

        #                $m{$qname1} = $earned{$qname1} / $gap;

        #reduced volatility for short tourneys
        if ( $games{$qname1} < 8 )
        {
          $earned{$qname1} *= 0.125 * ( $games{$qname1} );
        }

        # Provisional players under 1800 get extra 50% volatility
        if ( $ratedgames{$qname1} < $proviso && $hisrat{$qname1} < 1800 )
        {
          $earned{$qname1} *= 1.5;
        }

# Provisional players between 1800 to 2000 get extra, but decreasing volatility

        if ( $ratedgames{$qname1} < $proviso && $hisrat{$qname1} > 1799 )
        {
          $earned{$qname1} *= 1.5 + ( 1800 - $hisrat{$qname1} ) / 400;
        }

        # No more provisional treatment for anyone above 2000

        #bonus for earning more than 5 rating pts per game
        if ( $earned{$qname1} > 5 * $games{$qname1}
          && $games{$qname1} > $proviso )
        {
          if ( $games{$qname1} > 7 )
          {
            $bonus = int( 1.5 * ( $earned{$qname1} - 5 * $games{$qname1} ) );

            #bonus subject to multiplier boundaries (1800 -> 16, 2000 -> 10)
            if ( $rat0{$qname1} + $bonus > 2000 )
            {
              $exceededbonus = $rat0{$qname1} + $bonus - 2000;
              $bonus -= 0.375 * $exceededbonus;

   #note 0.375 because the 20% reduction for >1800 applies to those >2000 too.

              print "$qname1 crossed 2000! Effective bonus $bonus \n";

              if ( $rat0{$qname1} + $bonus > 1800 )
              {
                $exceededbonus = $rat0{$qname1} + $bonus - 1800;
                $bonus -= 0.2 * $exceededbonus;
                print "$qname1 crossed 1800! Effective bonus $bonus \n";
              }
            }
            $earned{$qname1} += $bonus;
          }
        }

        #penalty for losing more than 5 rating pts per game
        if ( -$earned{$qname1} > 5 * $games{$qname1}
          && $games{$qname1} > $proviso )
        {
          if ( $games{$qname1} > 7 )
          {
            $bonus = int( 1.5 * ( $earned{$qname1} + 5 * $games{$qname1} ) );
            $earned{$qname1} += $bonus;
            print "$qname1 crashed! Penalty $bonus \n";

          }
        }

#20% more rating change for players with legacy ratings
#		print "Check if $qname1 is active again - last played $lastplayed{$qname1}\n";
        $datediff = $toudate - $lastplayed{$qname1};
        if ( ( $datediff > $currency * 15000 ) && $ratedgames{$qname1} > 0 )
        {
          print
            "$qname1 was inactive and is now active, has played $ratedgames{$qname1} games\n";
          if ( $ratedgames{$qname1} > $proviso )
          {
            #this applies to established players of all ratings
            $earned{$qname1} *= 1.2;

            #Less change if player crosses boundaries
            if ( $hisrat{$qname1} + $earned{$qname1} > 1800 )
            {
              $earned{$qname1} *= 1
                + ( 1800 - ( $hisrat{$qname1} + $earned{$qname1} ) ) / 1000;
            }

            if ( $datediff > 50000 )
            {
              $oldrat{$qname1} = $hisrat{$qname1};
              $hisrat{$qname1}
                = ( $hisrat{$qname1} + 2 * $oldrat{$qname1} ) / 3
                + $earned{$qname1};
              $earned{$qname1} = $hisrat{$qname1} - $oldrat{$qname1};
              print "$qname1 is active again, rat change $earned{$qname1}\n";
            }

            #deflationary constant
            $month              = substr( $toudate,             4, 2 );
            $tyear              = substr( $toudate,             0, 4 );
            $lastyear{$qname1}  = substr( $lastplayed{$qname1}, 0, 4 );
            $lastmonth{$qname1} = substr( $lastplayed{$qname1}, 4, 2 );

            if ( $ratedgames{$qname1} > 0 )
            {
              $deflationrate = 0.25;
              $deflation
                = $deflationrate
                * ( 12 * ( $tyear - $lastyear{$qname1} )
                  + $month - $lastmonth{$qname1} );
              $earned{$qname1} -= $deflation;
            }

          }    #for non-newbies only
        }    #for player

        $newgames = $ratedgames{$qname1} + $games{$qname1};
        $pearned{$qname1} = $earned{$qname1};

        #                $m{$qname1}       = 0;

        # Cope with a player who becomes nonprovisional partway through
        $newtotalgames = $ratedgames{$qname1} + $hisgames[$secnum][$player];

        # eg   78 = 33 + 45 >50, so 17 /45 * prov + 28/45 * non prov
        if ( $newtotalgames > $proviso )
        {
          $pg  = $proviso - $ratedgames{$qname1};
          $npg = $newtotalgames - $proviso;

          $earned{$qname1}
            = ( $pg * $pearned{$qname1} + $npg * $earned{$qname1} )
            / $hisgames[$secnum][$player];
          $mix{$qname1}
            .= "$earned{$qname1} = ($pg*$pearned{$qname1}+ $npg*$earned{$qname1})/$hisgames[$secnum][$player]\n";

        }
        else
        {
          $earned{$qname1} = $pearned{$qname1};
          $mix{$qname1} .= "$pearned{$qname1}\n";
        }

        if ( $earned{$qname1} > 20 * $games{$qname1} )
        {
          #stop runaways
          $earned{$qname1} = 20 * $games{$qname1}
            + 0.5 * ( $earned{$qname1} - 20 * $games{$qname1} );
        }

        $earned2{$qname1} += $earned{$qname1};    # total for multipass
        $hisrat{$qname1}
          = $rat0{$qname1} + $earned2{$qname1};    #add up rating change

      }    # else (nonbye)

      if ( $hisrat{$qname1} < $floor )
      {
        $hisrat{$qname1}   = $floor;
        $$earned2{$qname1} = $floor - $rat0{$qname1};
      }
    }    # for $player

  }    # for each run

}    #end subroutine calcearned

sub tally
{
  my ( $secnum, $ub ) = @_;

  # and another final calculation
  for ( $player = 1; $player <= $secsize[$secnum]; $player++ )
  {
    $qname1 = $who[$secnum][$player];
    if ( $qname1 !~ /^. Bye/ )
    {
      $gain = $earned2{$qname1};

# print "$name1 $rat0{$name1} $earned{$name1}+$bonus{$name1}+$feedback{$name1}=$gain";
      $newrat{$qname1} = int( $rat0{$qname1} + $gain + 0.5 );

      # Version 2.30
      $newrat{$qname1} = $floor if $newrat{$qname1} < $floor;

      if ( $ratedgames{$qname1} == 0 )
      {
        $err = abs( $newrat{$qname1} - $rat0{$qname1} );
        if ( $err > $maxd )
        {
          $maxd   = $err;
          $whobad = "$qname1 $newrat{$qname1} - $rat0{$qname1} > $maxd";
        }
        $rat0{$qname1} = $newrat{$qname1};
      }
    }
  }

}

sub boundaries
{
  my ($secnum) = @_;
  $totalupfloor[$secnum] = 0;
  for ( $player = 1; $player <= $secsize[$secnum]; $player++ )
  {
    $qname1 = $who[$secnum][$player];
    if ( $qname1 !~ /^. Bye/ )
    {
      if (  ( $newrat{$qname1} < $floor )
        and ( $ratedgames{$qname1} >= $proviso ) )
      {
        $boundary{$qname1} = $floor - $newrat{$qname1};
        $totalupfloor[$secnum] += $boundary{$qname1};
        printf "%s upfloored by %+6.2f\n", $qname1, $boundary{$qname1};
        $newrat{$qname1} = $floor;
      }

      if ( $ratedgames{$qname1} == 0 )
      {
        if ( $newrat{$qname1} > $roof{$qname1} + 1 )
        {
          $boundary{$qname1} = $roof{$qname1} - $newrat{$qname1};
          printf "%s hit the ceiling, so %+6.2f\n", $qname1,
            $boundary{$qname1};
          $newrat{$qname1} = $roof{$qname1};
        }
      }
    }
  }
}

sub rmult
{    # refractive multiplier
  my ( $priorrat, $gap, $runs ) = @_;
  my ( $newrat, $oldrat, $change, $i );
  my @reducedmultiplier = map( $_ / $runs, @rmultiplier );

  # find starting band
  $i = @rlevel - 1;
  $i-- while $priorrat < $rlevel[$i];

  $oldrat = $priorrat;

##  carefully multiply if positive
  while ( $gap > 0 )
  {
    $change = $reducedmultiplier[$i] * $gap;
    $newrat = $oldrat + $change;

    if ( $newrat < $rlevel[ $i + 1 ] )
    {
      $gap = 0;
    }    # easy, no boundary crossed
    else
    {
      $gap -= ( $rlevel[ $i + 1 ] - $oldrat ) / $reducedmultiplier[$i];
      $oldrat = $rlevel[ $i + 1 ];
      $i++;
    }
  }

  # carefully multiply if negative
  while ( $gap < 0 )
  {
    $change = $reducedmultiplier[$i] * $gap;
    $newrat = $oldrat + $change;

    if ( $newrat > $rlevel[$i] ) { $gap = 0 }    # easy, no boundary crossed
    else
    {

      $gap += ( $oldrat - $rlevel[$i] ) / $reducedmultiplier[$i];
      $oldrat = $rlevel[$i];
      $i--;
      if ( $i < 0 ) { $gap = 0 }
    }

  }
  return $newrat - $priorrat;

}

sub nickname
{
  my ($name) = @_;
  my @parts = split( ' ', uc($name) );
  if ( @parts < 2 ) { return substr( $parts[0], 0, 4 ) }
  else
  {
    return sprintf(
      '%-4s',
      substr(
        substr( $parts[0], 0, 1 ) . substr( $parts[1], 0, 3 ) . '   ',
        0, 4
      )
    );
  }
}

sub squished
{
  my ($name) = @_;
  if ( $name =~ /^. Bye$/ ) { return $name }
  else
  {
    $name =~ s/[^A-Za-z]//g;    #Strip out nonalphe eg space, hyphen, comma
    return uc($name);
  }
}

sub ucbits
{    # Changes John van der Schoor to John Van Der Schoor }
  my $name = $_[0];
  return join( ' ', map( ucfirst($_), split( ' ', $name ) ) );
}

sub linear
{
  my $x = $_[0];
  my $y = 0.5 + $x / $lineark;
  $y = 0.05 if $y < 0.05;
  $y = 0.95 if $y > 0.95;
  return $y;
}

sub logit { return 1 / ( 1 + exp( -$_[0] / $logitk ) ) }

sub stfixer
{
  if ( $name =~ /^.Mohamm$/ )
  {
    $st = MYS;
  }

  if ( $name =~ /^.Muhamm$/ )
  {
    $st = MYS;
  }

  if ( $name =~ /^.Mohd$/ )
  {
    $st = MYS;
  }

  if ( $name =~ /^.Muhd$/ )
  {
    $st = MYS;
  }

  if ( $name =~ /^.Mark$/ )
  {
    $st = GBR;
  }

  if ( $name =~ /^.Abdullah$/ )
  {
    $st = PAK;
  }

  if ( $name =~ /^.Nutta$/ )
  {
    $st = THA;
  }

  if ( $name =~ /^.pong$/ )
  {
    $st = THA;
  }

  if ( $name =~ /^.Sitti$/ )
  {
    $st = THA;
  }

  if ( $name =~ /^.Siri$/ )
  {
    $st = THA;
  }

  if ( $name =~ /^.Rich$/ )
  {
    $st = AUS;
  }

  if ( $name =~ /^.Ola$/ )
  {
    $st = NGA;
  }

  if ( $name =~ /^.Olu$/ )
  {
    $st = NGA;
  }

  if ( $name =~ /^.Terry$/ )
  {
    $st = GBR;
  }

  if ( $name =~ /^.Kelly$/ )
  {
    $st = GBR;
  }

  if ( $name =~ /^.Lee Ch$/ )
  {
    $st = SGP;
  }

  if ( $name =~ /^.Yong$/ )
  {
    $st = SGP;
  }

  else
  {
    $st = $toustate;
  }

  #print "Player is from $st and Tourney is in $toustate \n";

}

__END__
