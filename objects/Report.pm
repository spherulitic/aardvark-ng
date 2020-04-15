package Report;

use strict;
use warnings;
use version; our $VERSION = qv('1');
use Carp;
use Data::Dumper;

use lib './modules';
use Constants;

sub add_item
{
  my $this = shift;
  my $item = shift;

  push @{ $this->{items} }, $item;
  return 1;
}

sub make_report_item
{
  my $item  = shift;
  my $level = shift;

  my $title = $item->{$REPORT_ITEM_TITLE_NAME};
  my $value = $item->{$REPORT_ITEM_VALUE_NAME};

  my $item_string = $EMPTY_STRING;
  $item_string .= Report::make_report_line( $level, $title, $value );

  if ( $item->{$REPORT_ITEM_SUBITEMS_NAME} )
  {
    my @subitems = @{ $item->{$REPORT_ITEM_SUBITEMS_NAME} };

    for my $i ( 0 .. scalar @subitems - 1 )
    {
      my $subitem_hashref = $subitems[$i];
      $item_string
        .= Report::make_report_item( $subitem_hashref, $level + 2 );
    }
  }
  return $item_string;
}

sub make_report_line
{
  my $padding = shift;
  my $title   = shift;
  my $value   = shift;

  my $line = $EMPTY_STRING;

  if ( !$padding )
  {
    my $left_margin  = ( ( $REPORT_WIDTH - 2 ) - length $title ) / 2;
    my $right_margin = ( ( $REPORT_WIDTH - 2 ) - length $title ) / 2
      + ( ( length $title ) % 2 );
    $line
      .= $REPORT_SIDE_BORDER
      . ( q{ } x $left_margin )
      . $title
      . ( q{ } x $right_margin )
      . $REPORT_SIDE_BORDER;
  }
  else
  {
    $line .= $REPORT_SIDE_BORDER . ( q{ } x $padding ) . $title;
    if ( defined $value )
    {
      $line
        .= ( q{.}
          x ( $REPORT_SPACING - ( ( length $title ) + ( length $value ) ) ) )
        . $value;
    }
    $line .= ( q{ } x ( ( $REPORT_WIDTH - length $line ) - 1 ) )
      . $REPORT_SIDE_BORDER;
  }

  return $line . $NEWLINE;
}

sub new
{
  my $this  = shift;
  my $title = shift;

  my $report = {
    title => $title,
    items => []
  };
  my $self = bless $report, $this;
  return $self;
}

sub to_string
{
  my $this = shift;

  my $report_blank_line = Report::make_report_line( 0, $EMPTY_STRING );
  my $report_string = ( $REPORT_TOP_BORDER x $REPORT_WIDTH ) . $NEWLINE;
  $report_string .= $report_blank_line;
  $report_string .= Report::make_report_line( 0, $this->{title} );
  $report_string .= $report_blank_line;

  my @items = @{ $this->{items} };

  for my $i ( 0 .. scalar @items - 1 )
  {
    $report_string
      .= Report::make_report_item( $items[$i], $REPORT_LEFT_MARGIN );
    $report_string .= $report_blank_line;
  }
  $report_string .= ( $REPORT_BOTTOM_BORDER x $REPORT_WIDTH ) . $NEWLINE;
  return $report_string . $NEWLINE;
}

1;
