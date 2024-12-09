julia -e 'using Pkg; Pkg.add(name = "PackageCompiler")'

julia --project=@. --startup-file=no -e 'using Pkg; Pkg.instantiate(); Pkg.status()'

julia --project=@. --startup-file=no -e '
using PackageCompiler;
PackageCompiler.create_app(pwd(), "StdEcgStats";
    cpu_target="generic;sandybridge,-xsaveopt,clone_all;haswell,-rdrnd,base(1)",
    include_transitive_dependencies=false,
    filter_stdlibs=false,
    incremental=true,
    precompile_execution_file=["test/runtests.jl"])
'