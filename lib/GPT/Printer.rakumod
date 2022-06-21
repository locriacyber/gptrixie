unit module GPT::Printer;

use GPT::Class;
use GPT::DumbGenerator;
use GPT::FileGenerator;
use GPT::FileFilter;
use GPT::HandleFileDeps;
use GPT::ListTypes;
use GPT::ListFiles;

sub is_header_std (IO $f --> Bool) {
  # TODO: make this non flaky
  $f.basename !~~ /^std/
}


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


sub print-att(AllTheThings $att, :%stages, Str() :@exclude-files) is export {
  # my @files = ();
  my @user-excludes = @exclude-files;

  sub stage (Str $name, &block) {
    if %stages{$name} -> \arg {
      block arg;
    }
  }

  stage "overview", {
    # if @files !== Empty {
    #   note "Displaying content of : " ~ @files.join(', ');
    # }
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
  }

  stage "list-deps", -> $list-deps {
    list-deps($att, $list-deps);
  }
  stage "list-types", {
    list-types($att);
  }
  stage "list-files", {
    list-files($att);
  }

  # if  {
  #  oog-config($ooc);
  #  oog-generate();
  # }
  
  stage "define-enum", -> $define-enum {
    my ($enum-name, $enum-pattern) := $define-enum.split(':');
    my CEnum $e .= new(:name($enum-name), :id(-1));
    for $att.files.kv -> $k, $v {
      if $v.IO.basename ne 'gccxml_builtins.h' and not is_header_std($v.IO) {
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
  
  stage "enum", {
    my %h = dg-generate-enums();
    put '## Enumerations';
    my %sortedh = sort-by-file($att, %h.values, @user-excludes);
    for %sortedh.kv -> $k, @v {
      put "\n# == {$att.files{$k}} ==\n";
      for @v -> $ob {
        put $ob<p6str>;
      }
    }
  }
  
  stage "struct", {
    my %h = dg-generate-structs();
    put '## Structures' ~ "\n";
    my %sortedh = sort-by-file($att, %h.values, @user-excludes);
    for %sortedh.kv -> $k, @v {
      put "\n# == {$att.files{$k}} ==\n";
      for @v.kv -> $i, $ob {
        if $ob<obj> ~~ Struct {
          if @v[$i + 1].defined and @v[$i + 1]<obj> ~~ AnonymousUnion and @v[$i + 1]<obj>.struct.defined {
            put @v[$i + 1]<p6str>;
          }
        }
        if !($ob<obj> ~~ AnonymousUnion and $ob<obj>.struct.defined) {
          put $ob<p6str>;
        }
      }
    }
  }
    
  stage "function", {
    put '## Extras stuff' ~ "\n";
    dg-generate-extra();
    my %h = dg-generate-functions();
    put '## Functions' ~ "\n";
    my %sortedh = sort-by-file($att, %h.values, @user-excludes);
    for %sortedh.kv -> $k, @v {
      put "\n# == {$att.files{$k}} ==\n";
      for @v -> $ob {
        put $ob<p6str>;
      }
    }
  }
  
  stage "extern", {
    put '## Externs' ~ "\n";
    my %h = dg-generate-externs();
    my %sortedh = sort-by-file($att, %h.values, @user-excludes);
    for %sortedh.kv -> $k, @v {
      put "\n# == {$att.files{$k}} ==\n";
      for @v -> $ob {
        put $ob<p6str>;
      }
    }
  }

}