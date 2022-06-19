unit module CastXML::Parser;

use XML;
use GPT::Class;

our $SILENT is export = False;

sub gpt-note (*@msg) is export {
   note |@msg unless $SILENT;
}

my constant $PLACEHOLDER = "GPTRIXIE_FIXME";

sub get-ast-from-header(:$xml-output, :$gmerge-stypedef) is export {
  my %types;
  my @typedefs;
  my %fields;
  my %structs;
  my @cfunctions;
  my @cenums;
  my %cunions;
  my %files;
  my @variables;
  
  my %times;

  my $t = now;

  %times<gccxml> = now - $t;
  $t = now;
  gpt-note "Parsing the XML file";
  my $xml = from-xml($xml-output);
  %times<parse-xml> = now - $t;
  $t = now;
  gpt-note "Doing magic";
  
  for $xml.elements(:TAG<File>) -> $filef {
     %files{$filef<id>} = $filef<name>;
  }

  for $xml.elements() -> $elem {
    given $elem.name {
      # == Types
      when 'FundamentalType' {
        my FundamentalType $t .= new(:id($elem<id>));
        $t.name = $elem<name>;
        %types{$t.id} = $t;
      }
      when 'FunctionType' {
         my FunctionType $t .= new(:id($elem<id>));
         $t.return-type-id = $elem<returns>;
         for $elem.elements(:name<Argument>) -> $arg {
           $t.arguments-type-id.push($arg<type>);
         }
         %types{$t.id} = $t;
      }
      when 'PointerType' {
        my PointerType $t .= new(:id($elem<id>));
        $t.ref-id = $elem<type>;
        $t.ref-type = %types{$t.ref-id} if %types{$t.ref-id}:exists;
        %types{$t.id} = $t;
      }
      when 'CvQualifiedType' {
        my QualifiedType $t .= new(:id($elem<id>));
        $t.ref-id = $elem<type>;
        $t.ref-type = %types{$t.ref-id} if %types{$t.ref-id}:exists;
        %types{$t.id} = $t;
      }
      when 'Typedef' {
        my TypeDefType $t .= new(:id($elem<id>));
        $t.ref-id = $elem<type>;
        $t.set-clocation($elem);
#         say $elem<name>;
#         say $t.ref-id;
        $t.ref-type = %types{$t.ref-id} if %types{$t.ref-id}:exists;
        $t.name = $elem<name>;
        %types{$t.id} = $t;
        @typedefs.push($t);
      }
      when 'ArrayType' {
        my $size = $elem<max>.subst('u', '') ~~ /"0xffffffffffffffff"/ ?? '' !! $elem<max>.subst('u', '') + 1;
        my ArrayType $t .= new(:id($elem<id>), :size($size));
        $t.ref-id = $elem<type>;
        %types{$t.id} = $t;
      }
      when 'ReferenceType' {
        my ReferenceType $t .= new(:id($elem<id>));
        $t.ref-id = $elem<type>;
        $t.ref-type = %types{$t.ref-id} if %types{$t.ref-id}:exists;
        %types{$t.id} = $t;
      }
      # == 'Real' Stuff
      when 'Field' {
        my $pf = Field.new();
        #$pf.set-clocation($elem);
        #$pf.file = %files{$pf.file-id};
        $pf.name = $elem<name>;
        $pf.type-id = $elem<type>;
        %fields{$elem<id>} = $pf;
        %structs{$elem<context>}.fields.push($pf) if %structs{$elem<context>}.defined;
        %cunions{$elem<context>}.members.push($pf) if %cunions{$elem<context>}.defined;
      }
      when 'Struct' {
        my $s = Struct.new;
        $s.name = $elem<name>.defined ?? $elem<name> !! $elem<mangled>;
        $s.name = $PLACEHOLDER if !$s.name.defined || $s.name eq '';
        $s.id = $elem<id>;
        #say "Struct : ", $s.id ~ $s.name;
        $s.set-clocation($elem);
        $s.file = %files{$s.file-id};
        %structs{$s.id} = $s;
        my StructType $t .= new(:id($s.id), :name($s.name));
        $t.set-clocation($elem);
        %types{$t.id} = $t;
      }
      when 'Class' { #FIXME need to add real stuff around that
        my ClassType $c .= new(:id($elem<id>), :name($elem<name>));
        %types{$c.id} = $c;
      }
      when 'Union' {
        my UnionType $t .= new(:id($elem<id>));
        %types{$t.id} = $t;
        $t.set-clocation($elem);
        my $u;
        if $elem<name>.defined and $elem<name> ne "" {
          $u = CUnion.new(:id($elem<id>));
          $u.name = $elem<name>;
        } else {
          $u = AnonymousUnion.new(:id($elem<id>));
          $u.struct = %structs{$elem<context>};
        }
        $u.set-clocation($elem);
        %cunions{$u.id} = $u;
      }
      when 'Enumeration' {
        my CEnum $enum .= new(:id($elem<id>), :name($elem<name>));
        my EnumType $t .= new(:id($elem<id>), :name($elem<name>));
        %types{$t.id} = $t;
        $enum.set-clocation($elem);
        $enum.file = %files{$enum.file-id};
        for @($elem.elements()) -> $enumv {
          my EnumValue $nv .= new(:name($enumv.attribs<name>), :init($enumv.attribs<init>));
          $enum.values.push($nv);
        }
        @cenums.push($enum);
      }
      when 'Function' {
        next if $elem<name> ~~ /^__/;
        my Function $f .= new(:name($elem<name>), :id($elem<id>));
        $f.returns-id = $elem<returns>;
        $f.set-clocation($elem);
        $f.file = %files{$f.file-id};
        for @($elem.elements()) -> $param {
          next if $param.name ne 'Argument';
          my FunctionArgument $a .= new(:name($param.attribs<name>));
          $a.set-clocation($param);
          $a.file = %files{$a.file-id};
          $a.type-id = $param<type>;
          $f.arguments.push($a);
        }
        @cfunctions.push($f)
      }
      when 'Variable' {
        if $elem<extern>.defined and $elem<extern> == 1 {
          my ExternVariable $e .= new(:id($elem<id>), :name($elem<name>));
          $e.type-id = $elem<type>;
          $e.set-clocation($elem);
          #$e.file = %files($e.file-id);
          @variables.push($e);
        }
      }
    }
  }
  

  #We probably can resolve every type now.
  sub resolvetype {
      my $change = True; #Do something like bubble sort, until we solve everytype, let's boucle
      while ($change) {
          $change = False;
          for %types.kv -> $id, $t {
              if $t ~~ IndirectType {
                  unless $t.ref-type:defined {
                      #say "Found an undef indirect id: "~ $t.ref-id;
                      $t.ref-type = %types{$t.ref-id};
                      $change = True;
                  }
                  CATCH {
                      default {
                          say $t.raku;
                      }
                  }
              }
          }
      }
  }
    resolvetype();

  sub merge-stypedef {
    for %types.kv -> $id, $t {
      if $t ~~ TypeDefType and $t.ref-type ~~ StructType {
        %types{$id} = $t.ref-type;
        $t.ref-type.name = $t.name;
        %structs{$t.ref-id}.name = $t.name;
      }
    }
  }
  #Handle functionType
  for %types.kv -> $k, $v {
    if $v ~~ FunctionType {
      $v.return-type = %types{$v.return-type-id};
      for $v.arguments-type-id -> $id {
        $v.arguments-type.push(%types{$id});
      }
    }
  }
  
  merge-stypedef() if $gmerge-stypedef;
  for @cfunctions -> $f {
    $f.returns = %types{$f.returns-id};
    for $f.arguments -> $a {
      $a.type = %types{$a.type-id};
    }
  }
  for %fields.kv ->  $id, $f {
    $f.type = %types{$f.type-id};
    if $f.type ~~ UnionType {
      %cunions{$f.type.id}.field = $f if %cunions{$f.type.id} ~~ AnonymousUnion;
    }
  }
  for %cunions.kv -> $k, $cu {
    if $cu ~~ AnonymousUnion {
      $cu.gen-name = $cu.struct.name ~ "_" ~ $cu.field.name ~ "_Union";
    }
  }
  for @variables -> $v {
    $v.type = %types{$v.type-id};
    #say $v.name ~ ' - ' ~ $v.type;
  }
  #say "Before FIX";
  #for %structs.kv -> $id, $s {
  #    say "ID : ", $id, " name = ", $s.name
  #}

  sub fix-struct-name { # CASTXML does not give a name to struct defined like typedef struct {} name
      # Also does not give nice name to anonymous struct in union
      #say "fix stuff";
      for %structs.keys -> $id {
          next if %structs{$id} !~~ Struct;
#          say "Id: ", $id, "name", %structs{$id}.name;
          if %structs{$id}.name eq $PLACEHOLDER {
              # Merging typedef struct {}
              for @typedefs -> $td {
                  if $td.ref-id eq $id {
 #                     say "merging struct ", $id , " with typedef ", $td.id;
                      %structs{$id}.name = $td.name;
                      %structs{$id}.id = $td.id;
                      %types{$id}.id = $td.id;
                      %types{$id}.name = $td.name;
                      %types{$td.id} = %types{$id};
                      %types{$id}:delete;
                      %structs{$td.id} = %structs{$id};
                      %structs{$id}:delete;
                      @typedefs.splice(@typedefs.first($td, :k), 1);
                      last;
                  }
              }
          }
      }
      # anonym union
      for %cunions.kv -> $id, $union {
          #say "Union : " ~ $union.id;
          for $union.members -> $field {
              #say "Field : " ~ $field.name ~ $field.type.id;
              if $field.type ~~ StructType {
                  #say "Find struct type in " ~ $union.name;
                  if %structs{$field.type.id}.name eq $PLACEHOLDER {
                      if $union !~~ AnonymousUnion {
                          %structs{$field.type.id}.name =
                                  $union.name ~ "_anonymousStruct" ~ $field.type.id;
                          %types{$field.type.id} = %structs{$field.type.id}.name;
                      } else {
                          %structs{$field.type.id}.name =
                                  "anonymousUnion{$id}_anonymousStruct" ~ $field.type.id;
                          %types{$field.type.id} = %structs{$field.type.id}.name;
                      }
                  }
              }
          }
      }
  }
  fix-struct-name();
  #say $_.id, " : ", $_.name  for %structs.values;
  #exit 1;
  %times<magic> = now - $t;
  gpt-note "Times -- gccxml: %times<gccxml> sec; xml parsing: %times<parse-xml> sec; magic: %times<magic>";
  
  
  if not $SILENT {
    note "\n==CSTRUCT==";
    for %structs.kv -> $k, $v {
      note "-$k : {$v.name}";
      for $v.fields -> $f {
        note "   {$f.type.Str} ({$f.type-id})  '{$f.name}'";
      }
    }

    note "==FUNCTIONS==";

    for @cfunctions -> $f {
      my @tmp;
      for $f.arguments -> $a {
        @tmp.push($a.type ~ ' ' ~ $a.name);
      }
      note $f.returns ~ "\t\t" ~ $f.name ~ '(' ~ @tmp.join(', ') ~ ')';
    }
  }

  
  my $att = AllTheThings.new;
  $att.files = %files;
  $att.types = %types;
  $att.functions = @cfunctions;
  $att.enums = @cenums;
  $att.structs = %structs;
  $att.unions = %cunions;
  $att.variables = @variables;
  return $att;
}
