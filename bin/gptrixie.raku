use v6;

# use XML;
use GPT::Class;
use GPT::Parser::CastXML;
use GPT::Processing;
use GPT::Printer;

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
         , Str  :$exclude-files #= exclude file when printing
        #  , Str :$files #= WIP Allow you to pick from which files you want to generate stuff. eg --files=myheader.h,mysubheader.h.
        #                #=
        #                #= You can also use file 'id' given by --list-files like   @f1,@f2
        #                #=
        #                #= You can also exclude file by putting - in front of the file
         , Bool :$merge-types = False #= Merge a typedef pointing to a struct type to the struct name
         , Str  :$gptfile #= Use the given GPT file to generate a module, all other (gpt) options are ignored
         , Str :$castxml-std = 'c89' #= prefer to use castxml, you need to specificy the C standard
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

  my %stages;
  %stages<overwiew>    = True;
  %stages<list-deps>   = $list-deps if $list-deps;
  %stages<list-types>  = True if $list-types;
  %stages<list-files>  = True if $list-files;
  %stages<define-enum> = $define-enum;
  %stages<enums>       = True if $enums or $all or $define-enum;
  %stages<structs>     = True if $structs or $all;
  %stages<function>    = True if $functions or $all;
  %stages<extern>      = True if $externs or $all;
  
  my Str @exclude-files = ();
  
  if $exclude-files -> $f {
    @exclude-files .append: $f.split
  }

  print-att($att, :%stages, :@exclude-files);

  note "Done";
}
