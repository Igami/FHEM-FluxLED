# Id ##########################################################################
# $Id:  $

# copyright ###################################################################
#
# 32_FluxLED.pm
#
# Copyright by igami
#
# This file is part of FHEM.
#
# FHEM is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation, either version 2 of the License, or (at your option) any later
# version.
#
# FHEM is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# FHEM.  If not, see <http://www.gnu.org/licenses/>.

# packages ####################################################################
package main;
  use strict;
  use warnings;

  use Blocking;
  use Color;

# variables ###################################################################
my $FluxLED_cmd = "flux_led";
my %FluxLED_preset = (
  "seven_color_cross_fade"   => 37,
  "red_gradual_change"       => 38,
  "green_gradual_change"     => 39,
  "blue_gradual_change"      => 40,
  "yellow_gradual_change"    => 41,
  "cyan_gradual_change"      => 42,
  "purple_gradual_change"    => 43,
  "white_gradual_change"     => 44,
  "red_green_cross_fade"     => 45,
  "red_blue_cross_fade"      => 46,
  "green_blue_cross_fade"    => 47,
  "seven_color_strobe_flash" => 48,
  "red_strobe_flash"         => 49,
  "green_strobe_flash"       => 50,
  "blue_stobe_flash"         => 51,
  "yellow_strobe_flash"      => 52,
  "cyan_strobe_flash"        => 53,
  "purple_strobe_flash"      => 54,
  "white_strobe_flash"       => 55,
  "seven_color_jumping"      => 56
);

# forward declarations ########################################################
sub FluxLED_Initialize($);

sub FluxLED_Define($$);
sub FluxLED_Undefine($$);
sub FluxLED_Set($@);
sub FluxLED_Get($@);

sub FluxLED_statusRequest($;$);
sub FluxLED_blocking_statusRequest($);
sub FluxLED_done($);
sub FluxLED_aborted($);

# initialize ##################################################################
sub FluxLED_Initialize($) {
  my ($hash) = @_;
  my $TYPE = "FluxLED";

  $hash->{DefFn}    = $TYPE."_Define";
  $hash->{UndefFn}  = $TYPE."_Undefine";
  $hash->{SetFn}    = $TYPE."_Set";
  $hash->{GetFn}    = $TYPE."_Get";
  $hash->{AttrFn}   = $TYPE."_Attr";

  $hash->{AttrList} =
    "disable:0,1 ".
    "interval ".
    "customPreset:textField-long ".
    $readingFnAttributes
  ;
}

# regular Fn ##################################################################
sub FluxLED_Define($$) {
  my ($hash, $def) = @_;
  my ($SELF, $TYPE, $MODE, @CONTROLLERS) = split(/[\s]+/, $def);

  return(
    "Usage: define <name> $TYPE ".
    "<(RGB|RGBW|W)> <CONTROLLERS> [<CONTROLLERS2> ...]"
  ) if($MODE !~ m/^(RGB|RGBW|W)$/ || @CONTROLLERS < 1);

  $hash->{MODE} = $MODE;
  $hash->{CONTROLLERS} = join(" ", @CONTROLLERS);

  readingsSingleUpdate($hash, "state", "Initialized", 1);

  FluxLED_statusRequest($hash);

  return;
}

sub FluxLED_Undefine($$) {
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);

  return;
}

sub FluxLED_Set($@) {
  my ($hash, @a) = @_;
  my $TYPE = $hash->{TYPE};
  my $MODE = $hash->{MODE};

  return("\"set $TYPE\" needs at least one argument") if(@a < 2);

  my $SELF     = shift @a;
  my $argument = shift @a;
  my $value    = join(" ", @a) if (@a);
  my %FluxLED_sets = (
    "on"            => "on:noArg",
    "off"           => "off:noArg",
    "statusRequest" => "statusRequest:noArg"
  );

  if($MODE =~ m/RGB/){
    my $preset = join(",", (AttrVal($SELF, "customPreset", "") =~ m/([A-Za-z-_.]+):/g));
    $preset .= "," if($preset);

    %FluxLED_sets = (
      %FluxLED_sets,
      "RGB"    => "RGB:textField",
      "clock"  => "clock:noArg",
      "custom" => "custom:textField",
      "preset" => "preset:".
                  "$preset".
                  "seven_color_cross_fade,".
                  "red_gradual_change,".
                  "green_gradual_change,".
                  "blue_gradual_change,".
                  "yellow_gradual_change,".
                  "cyan_gradual_change,".
                  "purple_gradual_change,".
                  "white_gradual_change,".
                  "red_green_cross_fade,".
                  "red_blue_cross_fade,".
                  "green_blue_cross_fade,".
                  "seven_color_strobe_flash,".
                  "red_strobe_flash,".
                  "green_strobe_flash,".
                  "blue_stobe_flash,".
                  "yellow_strobe_flash,".
                  "cyan_strobe_flash,".
                  "purple_strobe_flash,".
                  "white_strobe_flash,".
                  "seven_color_jumping",
      "speed"  => "speed:slider,0,1,100"
    );
  }
  if($MODE =~ m/W/){
    %FluxLED_sets = (%FluxLED_sets, "white" => "white:slider,0,1,100");
  }

  return(
    "Unknown argument $argument, choose one of ".
    join(" ", sort(values %FluxLED_sets))
  ) unless(exists($FluxLED_sets{$argument}));

  my $CONTROLLERS = $hash->{CONTROLLERS};
  my $cmd;

  if($argument =~ m/^on|off$/){
    $cmd = "$FluxLED_cmd --$argument $CONTROLLERS";

    readingsSingleUpdate($hash, "state", $argument, 1);
  }
  elsif($argument eq "RGB"){
    my ($R, $G, $B) = Color::hex2rgb($value);
    $cmd = "$FluxLED_cmd --on --color $R,$G,$B $CONTROLLERS";

    readingsBeginUpdate($hash);
    readingsBulkUpdateIfChanged($hash, "state", "on", 1);
    readingsBulkUpdate($hash, "RGB", $value, 1);
    readingsEndUpdate($hash, 1);
  }
  elsif($argument eq "clock"){
    $cmd = "$FluxLED_cmd --setclock $CONTROLLERS";
  }
  elsif($argument eq "custom"){
    my ($type, $colorlist) = split(/[\s]+/, $value, 2);
    my @colorlist = split(/[\s]+/, $colorlist);

    foreach (@colorlist){
      $_ = join(",", Color::hex2rgb($_)) if($_ =~ m/[0-9A-Fa-f]{6}/);
      $_ = "($_)";
    }

    $colorlist = join(" ", @colorlist);
    my $speed = ReadingsVal($SELF, "speed", 100);
    $cmd = "$FluxLED_cmd --on --$argument $type $speed \"$colorlist\" $CONTROLLERS";

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, ".custom_type", $type, 0);
    readingsBulkUpdate($hash, ".custom_colorlist", $colorlist, 0);
    readingsBulkUpdateIfChanged($hash, "state", "on", 1);
    readingsBulkUpdate($hash, "preset", $argument, 1);
    readingsEndUpdate($hash, 1);
  }
  elsif($argument eq "preset"){
    my $preset = AttrVal($SELF, "customPreset", undef);
    my $speed = ReadingsVal($SELF, "speed", 100);

    if($preset && $preset =~ m/$value:((jump|gradual|strobe)(\s+[0-9A-Fa-f]{6})+)/){
      FluxLED_Set($hash, $SELF, "custom", $1);

      return;
    }
    else{
      my $code = $FluxLED_preset{$value};
      $cmd = "$FluxLED_cmd --on --$argument $code $speed $CONTROLLERS";
    }
    readingsBeginUpdate($hash);
    readingsBulkUpdateIfChanged($hash, "state", "on", 1);
    readingsBulkUpdate($hash, "preset", $value, 1);
    readingsEndUpdate($hash, 1);
  }
  elsif($argument eq "speed"){
    my $preset = ReadingsVal($SELF, "preset", "seven_color_cross_fade");

    if($preset eq "custom"){
      my $type = ReadingsVal($SELF, ".custom_type", "gradual");
      my $colorlist = ReadingsVal($SELF, ".custom_colorlist", "(0,0,0)");
      $cmd = "$FluxLED_cmd --on --custom $type $value \"$colorlist\" $CONTROLLERS";
    }
    else{
      $preset = $FluxLED_preset{$preset};
      $cmd = "$FluxLED_cmd --on --preset $preset $value $CONTROLLERS";
    }

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "speed", $value, 1);
    readingsBulkUpdateIfChanged($hash, "state", "on", 1);
    readingsEndUpdate($hash, 1);
  }
  elsif($argument eq "white"){
    $cmd = "$FluxLED_cmd --on --color 0,0,0 --warmwhite $value $CONTROLLERS";

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "white", $value, 1);
    readingsBulkUpdateIfChanged($hash, "state", "on", 1);
    readingsEndUpdate($hash, 1);
  }

  FluxLED_statusRequest($hash, $cmd);

  return;
}

sub FluxLED_Get($@) {
  my ($hash, @a) = @_;
  my $TYPE = $hash->{TYPE};

  return("\"get $TYPE\" needs at least one argument") if(@a < 1);

  my $SELF = shift @a;
  my $argument = shift @a;
  my $value = join(" ", @a) if (@a);
  my %FluxLED_gets = (
    "clock"       => "clock:noArg",
    "controllers" => "controllers:noArg"
  );

  return(
    "Unknown argument $argument, choose one of ".
    join(" ", sort(values %FluxLED_gets))
  ) unless(exists($FluxLED_gets{$argument}));

  my $CONTROLLERS = $hash->{CONTROLLERS};
  my $ret;

  if($argument eq "clock"){
    $ret = `$FluxLED_cmd --getclock $CONTROLLERS`;
    my @ret =  split(/[\s]+/, $ret);
    $ret = @ret == 5 ? "$ret[3] $ret[4]" : undef;
  }
  elsif($argument eq "controllers"){
    $ret = `$FluxLED_cmd --scan`;
  }

  return $ret;
}

sub FluxLED_Attr(@) {
  my ($cmd, $SELF, $attribute, $value) = @_;
  my $hash = $defs{$SELF};
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - entering FluxLED_Attr");

  if($attribute eq "interval"){
    if($cmd eq "delete" || !looks_like_number($value) || $value < 30){
      delete($hash->{INTERVAL});
    }
    else{
      $hash->{INTERVAL} = $value;

      RemoveInternalTimer($hash);

      return if(IsDisabled($SELF));

      InternalTimer(
        gettimeofday() + $hash->{INTERVAL}, "FluxLED_statusRequest", $hash
      );
    }
  }
  elsif($attribute eq "customPreset" && $cmd eq "set"){
    return(
      "$SELF: Value \"$value\" is not allowed for preset!\n".
      "Must be a space-separated list of ".
      "\"<preset>:<jump|gradual|strobe> <RRGGBB> <RRGGBB> ...\" rows.\n".
      "e.g. RGB:gradual 000000 FF0000 000000 00FF00 000000 0000FF\n".
      "Only these characters are allowed: [alphanumeric - _ .]"
      ) if($value !~ m/^(\s*([A-Za-z-_.]+):(jump|gradual|strobe)(\s+[0-9A-Fa-f]{6})+)+$/);
  }

  return;
}

# blocking Fn #################################################################
sub FluxLED_statusRequest($;$) {
  my ($hash, $cmd) = @_;
  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};
  my $interval = InternalVal($SELF, "INTERVAL", undef);
  my $timeout = AttrVal($SELF, "timeout", "default");
  $timeout = 60 unless(looks_like_number($timeout));


  Log3($SELF, 5, "$TYPE ($SELF) - entering FluxLED_statusRequest");

  BlockingKill($hash->{helper}{RUNNING_PID})
    if(defined($hash->{helper}{RUNNING_PID}));

  if($interval){
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday() + $interval, "FluxLED_statusRequest", $hash);
  }

  # unless(-X $FluxLED_cmd){
  #   readingsSingleUpdate($hash, "state", "error", 1);
  #   Log3(
  #       $SELF, 1, "$TYPE ($SELF) - "
  #     . "please check if flux_led ist installed and available at path $FluxLED_cmd"
  #   );
  #
  #   return;
  # }

  Log3($SELF, 5, "$TYPE ($SELF) - BlockingCall FluxLED_blocking_statusRequest");

  my $arg = $cmd ? "$SELF||$cmd" : $SELF;

  $hash->{helper}{RUNNING_PID} = BlockingCall(
    "FluxLED_blocking_statusRequest", $arg, "FluxLED_done",
    $timeout, "FluxLED_aborted", $SELF
  # ) unless(exists($hash->{helper}{RUNNING_PID}));
  );

  return;
}

sub FluxLED_blocking_statusRequest($) {
  my ($SELF, $cmd) = split("\\|\\|", shift);
  my ($hash) = $defs{$SELF};
  my $TYPE = $hash->{TYPE};
  my $IP = (split(" ", $hash->{CONTROLLERS}))[0];
  my $ret = `$cmd` if($cmd);
  my @ret = split("\n", `$FluxLED_cmd $IP --timers`);

  Log3($SELF, 5, "$TYPE ($SELF) - entering FluxLED_blocking_statusRequest");

  if($ret[0] =~ m/(ON|OFF)\s+\[Warm White: (\d+)%/){
    $ret[7] = "mode|white";
    $ret[8] = "white|$2";
  }
  elsif($ret[0] =~ m/(ON|OFF)\s+\[Color: \((\d+), (\d+), (\d+)/){
    $ret[7] = "mode|color";
    $ret[8] = "RGB|" . uc(Color::rgb2hex($2, $3, $4));
  }
  elsif($ret[0] =~ m/(ON|OFF)\s+\[Pattern: ([A-Za-z ]+) \(Speed (\d+)%/){
    $ret[7] = "mode|pattern";
    $ret[8] = "preset|" . lc($2);
    $ret[9] = "speed|$3";
    $ret[8] =~ s/\s+/_/g;
  }
  elsif($ret[0] =~ m/(ON|OFF)\s+\[Custom pattern \(Speed (\d+)%/){
    $ret[7] = "mode|custom";
    $ret[8] = "preset|custom";
    $ret[9] = "speed|$2";
  }
  else{
    return("state|error");
  }

  $ret[0] = "state|" . lc($1);

  for(my $i = 1; $i < 7; $i++){
    $ret[$i] = "timer-$i|" . (split(": ", $ret[$i], 2))[1];
  }

  return (join("||", $SELF, @ret));
}

sub FluxLED_done($) {
  my ($string) = @_;
  my ($SELF, @readings) = split("\\|\\|", $string);
  my ($hash) = $defs{$SELF};
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - entering FluxLED_done");

  # delete($hash->{helper}{RUNNING_PID});

  return unless(@readings);

  readingsBeginUpdate($hash);

  foreach (@readings){
    my ($reading, $value) = split("\\|", $_);

    readingsBulkUpdate($hash, $reading, $value);
  }

  readingsEndUpdate($hash, 1);

  return;
}

sub FluxLED_aborted($) {
  my ($SELF) = @_;
  my $hash = $defs{$SELF};
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 1, "$TYPE ($SELF) - entering FluxLED_aborted");

  delete($hash->{helper}{RUNNING_PID});

  readingsSingleUpdate($hash, "state", "error", 1);

  return;
}

1;

# commandref ##################################################################
=pod
=item device
=item summary    controlls different WLAN LED Controller
=item summary_DE steuert verschiedene WLAN LED Controller

=begin html

<a name="FluxLED"></a>
<h3>FluxLED</h3>
<div>
  <ul>
    FluxLED steuert über das
    <a href="https://github.com/beville/flux_led">
      <u>flux_led Skript</u>
    </a> verschiedene WLAN LED Controller.<br>
    <br>
    Vorraussetzungen:
    <ul>
      Es wird das
      <a href="https://github.com/beville/flux_led">
        <u>flux_led Skript</u>
      </a>
      benötig.<br>
      Dies kann über pip installiert werden:<br>
      <code>"sudo pip install flux_led"</code>
      .
    </ul>
    <br>
    <a name="FluxLEDdefine"></a>
    <b>Define</b>
    <ul>
      <code>
        define &lt;name&gt; FluxLED
        &lt;(RGB|RGBW|W)&gt; &lt;CONTROLLER1&gt; [&lt;CONTROLLER2&gt; ...]
      </code><br>
      Es muss angegebenen werden ob der Controller als RGB, RGBW oder W
      betrieben wird. Danach werden durch Leerzeichen getrennt die IP Adressen
      aller Controller angegebenen die zusammen geschaltet werden sollen. Bei
      einem statusRequest wird immer nur der erste Controller ausgelesen.
    </ul><br>
    <a name="FluxLEDset"></a>
    <b>Set</b>
    <ul>
      <li>
        <code>on</code><br>
        Schalatet alle Controller ein, dabei wird der letze Zustand wiederhergestellt.
      </li>
      <li>
        <code>off</code><br>
        Schalatet alle Controller aus.
      </li>
      <li>
        <code>statusRequest</code><br>
        Fragt den Status vom ersten Controller ab.
      </li>
      <li>
        <code>RGB RRGGBB</code><br>
        Schaltet die Controller auf die angegebene Farbe.
      </li>
      <li>
        <code>custom &lt;(jump|gradual|strobe)&gt; &lt;RRGGBB&gt; &lt;RRGGBB&gt; ... </code><br>
        Startet eine benutzerdefinierte Sequenz.
      </li>
      <li>
        <code>preset</code><br>
        Startet eine vorgegebene Sequenz.
      </li>
      <li>
        <code>speed</code><br>
        Legt die Geschwindigkeit für die letzte Sequenz fest.
      </li>
      <li>
        <code>white</code><br>
        Schaltet den Weiß-Kanal auf den angegebenen Wert.
      </li>
      <li>
        <code>clock</code><br>
        Setzt die Uhrzeit des Controllers auf die aktuelle Systemuhrzeit.
      </li>
    </ul><br>
    <a name="FluxLEDreadings"></a>
    <b>Readings</b><br>
    <ul>
      <li>
        <code>state (on|off|error)</code><br>
      </li>
      <li>
        <code>mode (white|color|preset|custom)</code><br>
      </li>
      <li>
        <code>speed</code><br>
        Geschwindigkeit der Sequenz.
      </li>
      <li>
        <code>present</code><br>
        Zuletzt benutze Sequenz.
      </li>
      <li>
        <code>timer-(1..6)</code><br>
        Die auf dem Controller eingestellten Timer.
      </li>
    </ul><br>
    <a name="FluxLEDattr"></a>
    <b>Attribute</b>
    <ul>
      <li>
        <code>customPreset</code><br>
        Eine Leerzeichen-getrennte Liste von
        "&lt;preset&gt;:&lt;(jump|gradual|strobe)&gt; &lt;RRGGBB&gt;
        &lt;RRGGBB&gt; ..." Reihen.
      </li>
      <li>
        <code>disable 1</code><br>
        Es werden keine weitere statusRequest durchgeführt.
      </li>
      <li>
        <code>interval &lt;interval&gt;</code><br>
        Legt fest in welchem Abstand der Controller abgefragt werden soll.<br>
        Wenn das Attribut nicht gesetzt, erfolgt dies nur nach dem absetzen
        eines Befehls. Ein Regelmäßiges Abfragen kann sinnvoll sein, wenn man
        den Controller noch anders steuert.
      </li>
      <li>
        <a href="#readingFnAttributes">
          <u><code>readingFnAttributes</code></u>
        </a>
      </li>
    </ul>
  </ul>
</div>

=end html
=cut
