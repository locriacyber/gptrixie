unit module CastXML::Parser;

use XML;
use GPT::Class;
use GPT::Processing;

sub timethis (Str $task_desc, &code) is export {
  $*ERR.print: $task_desc;
  $*ERR.print: "... ";
  my $start = now;
  my \res := code;
  my $time = now - $start;
  $*ERR.print: "$time sec\n";
  res
}

sub get-ast-from-header(IO::Handle:D :$of, :$xml-output, Bool:D :$merge-types) is export {
  ENTER my \backup = $*OUT;
  LEAVE $*OUT = backup;

  $*OUT = $of; # 'temp' or 'my' not working

  my @typedefs;
  my %fields;

  # my $time_start = now;
  # my $time_external = now - $time_start; $time_start = now;
  
  my XML::Document:D $xml = timethis "Parsing the XML file", {
    from-xml($xml-output);
  };

  # my $time_parse = now - $time_start; $time_start = now;

  # LEAVE {
  #   my $time_magic = now - $time_start;
  #   note "Times -- gccxml: $time_gccxml sec; xml parsing: $times_parse-xml sec; magic: %times_magic";
  # }
  
  my $att = AllTheThings.new;

  timethis "Get filenames", {
    for $xml.elements(:TAG<File>) -> $filef {
      $att.files{$filef<id>} = $filef<name>;
    }
  };

  timethis "Initial pass", {
    for $xml.elements() -> $elem {
      add-stuff-from-xml-element $att, :$elem, :@typedefs, :%fields;
    }
  };

  timethis "resolvetype", { resolvetype($att.types) };

  #| magic
  timethis "Post processing pass", { mangle-names $att, :%fields, :$merge-types };

  timethis "fix-struct-name", { fix-struct-name $att, :@typedefs };
  
  return $att;
}
