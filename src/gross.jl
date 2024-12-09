function total_gross(dfs::Vector{DataFrame}, title_column::Pair{Symbol, Vector{String}})

    gross_df = DataFrame()
    for df in dfs
        push!(gross_df, df[end, 2:end])
    end
    insertcols!(gross_df, 1, title_column)

    return gross_df
end
