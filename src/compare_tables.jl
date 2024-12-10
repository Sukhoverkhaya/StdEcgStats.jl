function gross_delta(old_gross::DataFrame, new_gross::DataFrame, n_last_rows::Int = -1)

    (size(old_gross) != size(new_gross)) && error("Tables to comparison must be the same length")

    nrows, _ = size(new_gross)
    rows_rng = (n_last_rows == -1) ? (1:nrows) : (nrows-n_last_rows+1:nrows)

    oldM = Matrix(old_gross[rows_rng, 2:end])
    newM = Matrix(new_gross[rows_rng, 2:end])
    deltaM = newM - oldM

    txt_delta = map(deltaM) do x
        str = round(x, digits = 2) .|> string
        !isnan(x) && (x > 0) && (str = '+'*str)
        '''*str
    end

    delta_df = DataFrame(names(new_gross)[2:end] .=> eachcol(txt_delta))
    insertcols!(delta_df, 1, first(names(new_gross)) => new_gross[rows_rng,1])

    return delta_df
end

function gross_delta(old_path::String, new_path::String, n_last_rows::Int = -1)
    old_gross = CSV.read(old_path, DataFrame)
    new_gross = CSV.read(new_path, DataFrame)

    return gross_delta(old_gross, new_gross, n_last_rows)
end

"""
Сравнение таблиц статистики между двумя прогонами
"""
function compare_stata_tables(old_tables::AbstractString, new_tables::AbstractString, outpath::AbstractString)

    dst = joinpath(outpath, "comparison_$(formatted_now())")
    mkpath(dst)

    write(open(joinpath(dst, "readme.txt"), "w"), join(pairs((;old_tables, new_tables)), '\n'))

    for table in ("qrs_detector", "qrs_forms", "durations_err")
        delta = gross_delta(joinpath.((old_tables, new_tables), table*".csv")..., 1)[:,2:end]

        CSV.write(joinpath(dst, "DELTA_$table.csv"), delta)
    end

    for table_type in ("По записям", "По сегментам")
        mkpath(joinpath(dst, table_type))
        for gross_type in ("GROSS_Ритмы", "GROSS_Эктопические комплексы", "GROSS_Узловое проведение")
            grosspath = joinpath("Ритмы и аритмии", table_type, gross_type*".csv")
            delta = gross_delta(joinpath.((old_tables, new_tables), grosspath)...)

            table_name = split(gross_type, "GROSS")[end]
            CSV.write(joinpath(dst, table_type, "DELTA$table_name.csv"), delta)
        end
    end
end
