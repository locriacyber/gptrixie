unit module GPT::Processing;

use XML;
use GPT::Class;

sub timethis (Str $task_desc, &code) is export {
  $*ERR.print: $task_desc;
  $*ERR.print: "... ";
  my $start = now;
  my \res := code;
  my $time = now - $start;
  $*ERR.print: "$time.fmt('%.2f') sec\n";
  res
}

my constant $PLACEHOLDER = "GPTRIXIE_FIXME";

sub add-stuff-from-xml-element
  (AllTheThings $att is rw, XML::Element:D :$elem, :@typedefs, :%fields)
is export {
  my (:%structs, :%types, :%unions, :%files, :@enums, :@functions, :@variables) := $att;

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
      # say $elem<name>;
      # say $t.ref-id;
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
      %unions{$elem<context>}.members.push($pf) if %unions{$elem<context>}.defined;
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
      %unions{$u.id} = $u;
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
      @enums.push($enum);
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
      @functions.push($f)
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
sub resolvetype(%types) is export {
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
            note "Error: " ~ $t.raku;
          }
        }
      }
    }
  }
}

sub fix-struct-name (AllTheThings $att is rw, :@typedefs) is export { # CASTXML does not give a name to struct defined like typedef struct {} name
  my (:%structs, :%types, :%unions, *%) := $att;

  #say "Before FIX";
  #for %structs.kv -> $id, $s {
  #    say "ID : ", $id, " name = ", $s.name
  #}
  
  # LEAVE { say $_.id, " : ", $_.name  for %structs.values; }

  # Also does not give nice name to anonymous struct in union
  #say "fix stuff";
  for %structs.keys -> $id {
      next if %structs{$id} !~~ Struct;
      # say "Id: ", $id, "name", %structs{$id}.name;
      if %structs{$id}.name eq $PLACEHOLDER {
          # Merging typedef struct {}
          for @typedefs -> $td {
              if $td.ref-id eq $id {
                    # say "merging struct ", $id , " with typedef ", $td.id;
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
  for %unions.kv -> $id, $union {
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

sub mangle-names ($att is rw, :%fields, Bool:D :$merge-types) is export {
    #Handle functionType
  for $att.types.kv -> $k, $v {
    if $v ~~ FunctionType {
      $v.return-type = $att.types{$v.return-type-id};
      for $v.arguments-type-id -> $id {
        $v.arguments-type.push($att.types{$id});
      }
    }
  }
  
  if $merge-types {
    for $att.types.kv -> $id, $t {
      if $t ~~ TypeDefType and $t.ref-type ~~ StructType {
        $att.types{$id} = $t.ref-type;
        $t.ref-type.name = $t.name;
        $att.structs{$t.ref-id}.name = $t.name;
      }
    }
  }
  for $att.functions -> $f {
    $f.returns = $att.types{$f.returns-id};
    for $f.arguments -> $a {
      $a.type = $att.types{$a.type-id};
    }
  }
  for %fields.kv ->  $id, $f {
    $f.type = $att.types{$f.type-id};
    if $f.type ~~ UnionType {
      $att.unions{$f.type.id}.field = $f if $att.unions{$f.type.id} ~~ AnonymousUnion;
    }
  }
  for $att.unions.kv -> $k, $cu {
    if $cu ~~ AnonymousUnion {
      $cu.gen-name = $cu.struct.name ~ "_" ~ $cu.field.name ~ "_Union";
    }
  }
  for $att.variables -> $v {
    $v.type = $att.types{$v.type-id};
    #say $v.name ~ ' - ' ~ $v.type;
  }
}
