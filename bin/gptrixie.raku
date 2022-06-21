use v6;

use XML;
use GPT::Class;
use GPT::DumbGenerator;
use GPT::FileGenerator;
use GPT::FileFilter;
use GPT::HandleFileDeps;
use GPT::ListTypes;
use GPT::ListFiles;
use CastXML::Parser;

sub sort-by-file($att, @array, @user-excludes) {
  my %toret;
  for @array -> %s {
    %toret{%s<obj>.file-id}.push(%s) if files-filter(%s<obj>.file-id, $att.files{%s<obj>.file-id}, @user-excludes);
  }
  for %toret.keys -> $k {
    @(%toret{$k}).=sort: {$^a<obj>.start-line > $^b<obj>.start-line};
  }
  return %toret;
}

sub create-xml(Proc:D $prun --> Str:D) {
  die "Error with castxml : " ~ $prun.err.slurp if $prun.exitcode != 0;
  my $serr = $prun.err.slurp;
  my $xml-output = $prun.out.slurp;
  die "Error: no XML produced, " ~ $serr if $xml-output eq "";
  $xml-output;
}

my %*SUB-MAIN-OPTS = :named-anywhere #`(allow named variables at any location);

sub MAIN(
          $header-file #= The header file
         , IO(Str) :$o #= Output file
         , Bool :$enums #= Generate enumerations
         , Bool :$functions #= Generate functions
         , Bool :$structs #= Generate structures and unions
         , Bool :$externs #= Generate extern declaration
         , Str :$define-enum #= Try to generate enumeration from #define using the given starting pattern
         , Str :$ooc #= Do nothing        
         , Bool :$debug  = False #= print parsed information, for debugging
         , Bool :$list-types #= Mostly for debug purpose, list all the C type found
         , Bool :$list-files #= List all the files involved
         , Str  :$list-deps #= List the dependancy from other files for this file, based on type used
         , Str :$files #= WIP Allow you to pick from which files you want to generate stuff. eg --files=myheader.h,mysubheader.h.
                       #=
                       #= You can also use file 'id' given by --list-files like   @f1,@f2
                       #=
                       #= You can also exclude file by putting - in front of the file
         , Bool :$merge-types = False #= Merge a typedef pointing to a struct type to the struct name
         , Str  :$gptfile #= Use the given GPT file to generate a module, all other (gpt) options are ignored
         , Str :$castxml-std = 'c89' #= allow for gptrixie to use castxml, you need to specificy the C standard
         , *@tooloptions #= remaining options are passed to gccxml. eg -I /path/needed/by/header
         ) {
  my IO::Handle:D $of = do
    if not $o.defined {
      if $*OUT.t {
        die "I refuse to output to TTY. Specify '-o /dev/stdout' ignore this.";
      }
      $*OUT
    } else {
      $o.open: :w
    };
  
  # LEAVE { $of.flush; };

  # our $all = $all;
  my $all = False;
  if not ($enums or $functions or $structs or $externs) {
    note "Not asked to generate anything. I guess you want to generate everything.";
    $all = True;
  }

  if $define-enum.defined and ! $define-enum.index(':').defined {
      die "The define-enum option must be of the form enumname:pattern";
  }


  # my $gmerge-stypedef = $merge-types;

  if $gptfile.defined {
    !!! "disabled due to bitrot"
    # read-gpt-file($gptfile);
    # $gmerge-stypedef = $GPT::FileGenerator::merge-typedef-struct;
    # generate-modules($att);
    # return 0;
  }

  my @commands = (
    'castxml',
    ('--castxml-gccxml', "-std=$castxml-std", '-o', '-', $header-file, |@tooloptions),
  ), (
    %*ENV<GPT_GCCXML> || 'gccxml',
    ($header-file, "-fxml=-", |@tooloptions),
  );
  my $xml-output;
  for @commands -> ($command, @arg) {
    my $prun = Proc.new(:out, :err);
    if not $prun.spawn($command, @arg) {
      $of.put: "Cannot find command: $command";
      next;
    }
    $xml-output = timethis "Calling: <$prun.command()>", { create-xml($prun) };
    last;
  }
  if not $xml-output {
    note "No XML generated. Tried:";
    for @commands -> $a {
      note "  " ~ @commands;
    }
    die;
  } 
    
  my AllTheThings $att = get-ast-from-header(:$of, :$xml-output, :$merge-types);

  if $debug {
    note "\n==CSTRUCT==";
    for $att.structs.kv -> $k, $v {
      note "-$k : {$v.name}";
      for $v.fields -> $f {
        note "   {$f.type.Str} ({$f.type-id})  '{$f.name}'";
      }
    }

    note "==FUNCTIONS==";

    for $att.functions -> $f {
      my @tmp;
      for $f.arguments -> $a {
        @tmp.push($a.type ~ ' ' ~ $a.name);
      }
      note $f.returns ~ "\t\t" ~ $f.name ~ '(' ~ @tmp.join(', ') ~ ')';
    }
  }

  my @files = ();
  my @user-excludes = ();
  if $files {
    for $files.split(',') {
      if $_.starts-with('-') {
        @user-excludes.push($_.substr(1));
      } else {
        @files.push($_);
      }
    }
  }
  if @files !== Empty {
    note "Displaying content of : " ~ @files.join(', ');
  }
  if @user-excludes !== Empty {
    note "Excluding content of : " ~ @user-excludes.join(', ');
  }
  
  note 'Number of things founds';
  note '-Types: ' ~ $att.types.elems;
  note '-Structures: ' ~ $att.structs.elems;
  note '-Unions: ' ~ $att.unions.elems;
  note '-Enums: ' ~ $att.enums.elems;
  note '-Functions: ' ~ $att.functions.elems;
  note '-Variables: ' ~ $att.variables.elems;
  note '-Files: ' ~ $att.files.elems;
  note "Generating Raku file...";

  if $list-deps.defined {
    list-deps($att, $list-deps);
  }
  if $list-types {
    list-types($att);
  }
  if $list-files {
    list-files($att);
  }
  #if $ooc {
  #  oog-config($ooc);
  #  oog-generate();
  #}
  
  if $define-enum {
    my ($enum-name, $enum-pattern) := $define-enum.split(':');
    my CEnum $e .= new(:name($enum-name), :id(-1));
    for $att.files.kv -> $k, $v {
      if $v.IO.basename ne 'gccxml_builtins.h' and $v.IO.basename !~~ /^std/ {
        my $fh = open $v;
        for $fh.lines -> $line {
          if $line ~~ /^"#"\s*"define" \s+ ($enum-pattern\S*) \s+ (<-[\/]>+)/ {
            my EnumValue $ev .= new;
            $ev.name = $0;
            $e.file-id = $k;
            $ev.init = $1;
            $e.values.push($ev);
          }
        }
      }
    }
    if $e.values.elems !== 0 {
      $att.enums.push($e);
    }    
  }
  # GENERATE STUFF (exclusion are made in sort-by-file)
  dg-init($att);
  if $enums or $all or $define-enum {
    my %h = dg-generate-enums();
    $of.put: '## Enumerations';
    my %sortedh = sort-by-file($att, %h.values, @user-excludes);
    for %sortedh.kv -> $k, @v {
      $of.put: "\n# == {$att.files{$k}} ==\n";
      for @v -> $ob {
        $of.put: $ob<p6str>;
      }
    }
  }
  
  if $structs or $all {
    my %h = dg-generate-structs();
    $of.put: '## Structures' ~ "\n";
    my %sortedh = sort-by-file($att, %h.values, @user-excludes);
    for %sortedh.kv -> $k, @v {
      $of.put: "\n# == {$att.files{$k}} ==\n";
      for @v.kv -> $i, $ob {
        if $ob<obj> ~~ Struct {
          if @v[$i + 1].defined and @v[$i + 1]<obj> ~~ AnonymousUnion and @v[$i + 1]<obj>.struct.defined {
            $of.put: @v[$i + 1]<p6str>;
          }
        }
        if !($ob<obj> ~~ AnonymousUnion and $ob<obj>.struct.defined) {
          $of.put: $ob<p6str>;
        }
      }
    }
  }
    
  if $functions or $all {
    $of.put: '## Extras stuff' ~ "\n";
    dg-generate-extra();
    my %h = dg-generate-functions();
    $of.put: '## Functions' ~ "\n";
    my %sortedh = sort-by-file($att, %h.values, @user-excludes);
    for %sortedh.kv -> $k, @v {
      $of.put: "\n# == {$att.files{$k}} ==\n";
      for @v -> $ob {
        $of.put: $ob<p6str>;
      }
    }
  }
  
  if $externs or $all {
    $of.put: '## Externs' ~ "\n";
    my %h = dg-generate-externs();
    my %sortedh = sort-by-file($att, %h.values, @user-excludes);
    for %sortedh.kv -> $k, @v {
      $of.put: "\n# == {$att.files{$k}} ==\n";
      for @v -> $ob {
        $of.put: $ob<p6str>;
      }
    }
  }
  note "Done";
}
