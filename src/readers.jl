mutable struct MarkPart # Только нужные поля из разметки
    fs::Union{Nothing, Float64}
    QRS_onset::Vector{Int}
    QRS_end::Vector{Int}
    QRS_form::Vector{String}
    P_onset::Union{Nothing, Vector{Int}}
    P_end::Union{Nothing, Vector{Int}}
    T_end::Union{Nothing, Vector{Union{Missing, Int}}}
    workzone::BitVector
    events::Vector{Dict{String, Any}} # чтобы не тянуть Descriptors, для наших целей всё равно нужны только текстовые ключи событий + маски
end

# действия с полями разметки
peak_pos(r::UnitRange{Int}) = round(Int, (first(r)+last(r))/2)

fs(m::MarkPart) = m.fs

workzone(m::MarkPart) = m.workzone

QRS_bounds(m::MarkPart; consider_workzone::Bool = false) = begin
    i1, i2 = 1, lastindex(m.QRS_onset)
    consider_workzone && (i1 = findfirst(m.workzone); i2 = findlast(m.workzone))

    return range.(m.QRS_onset, m.QRS_end)[i1:i2]
end

P_bounds(m::MarkPart; consider_workzone::Bool = false) = begin
    i1, i2 = 1, lastindex(m.QRS_onset)
    consider_workzone && (i1 = findfirst(m.workzone); i2 = findlast(m.workzone))
    wzone = first(m.QRS_onset[i1]):last(m.QRS_end[i2])
    bounds = isnothing(m.P_onset) ? missing : range.(m.P_onset, m.P_end)
    !ismissing(bounds) && filter!(x -> (first(x) >= first(wzone)) && (last(x) <= last(wzone)), bounds)
    return bounds
end

T_bounds(m::MarkPart; consider_workzone::Bool = false) = begin
    i1, i2 = 1, lastindex(m.QRS_onset)
    consider_workzone && (i1 = findfirst(m.workzone); i2 = findlast(m.workzone))

    bounds = isnothing(m.T_end) ? missing : m.T_end[i1:i2] # T_end параллелен QRS_onset и QRS_end
    return bounds
end

QT_bounds(m::MarkPart; consider_workzone::Bool = false) = begin
    i1, i2 = 1, lastindex(m.QRS_onset)
    consider_workzone && (i1 = findfirst(m.workzone); i2 = findlast(m.workzone))

    bounds = isnothing(m.T_end) ? missing : [ismissing(t) ? missing : q:t for (q, t) in zip(m.QRS_onset, m.T_end)][i1:i2]
    return bounds
end

R_peaks(m::MarkPart; consider_workzone::Bool = false) = peak_pos.(QRS_bounds(m; consider_workzone))

QRS_form(m::MarkPart; consider_workzone::Bool = false) = @views consider_workzone ? m.QRS_form[workzone(m)] : m.QRS_form

events(m::MarkPart; consider_workzone::Bool = false) = begin
    events = lineup_events(m.events)
    if consider_workzone
        for key in keys(events)
            @views events[key] = events[key][workzone(m)]
        end
    end
    return events
end

"""
Преобразовать событие в набор клоючей
"""
function _keyset(key::String, ev::Dict{String, Any})::String
    parts = filter(x -> typeof(x) == String, collect(values(ev)))
    keyset = join(parts, '-')
    fullset = "{$key}"
    !isempty(keyset) && (fullset = join((fullset, keyset), '-'))

    return fullset
end

"""
Развернуть иерархичную структуру событий в линейный словарь набор_ключей => битовая маска
"""
function lineup_events(events::Vector{Dict{String, Any}})::Dict{String, BitVector}
    list = Dict{String, BitVector}()
    for ev in events
        for key in ("base_rhythm", "ectopic", "nodal_conduction")
            if typeof(ev[key]) <: Vector
                for x in ev[key]
                    list[_keyset(key, x)] = Bool.(x["mask"])
                end
            else
                list[_keyset(key, ev[key])] = Bool.(ev[key]["mask"])
            end
        end
    end

    return list
end

# чтение частичной разметки
fullpath(rootdir::AbstractString, fn::AbstractString, ext::AbstractString) = joinpath(rootdir, join((fn, ext), '.'))

function read_markups(markpath, binpath, ref_author, test_author)
    allmkps = readdir(markpath) .|> splitext .|> first |> unique
    common_mkps = filter(x ->
        isdir(fullpath(markpath, x, ref_author)) &&
        isdir(fullpath(markpath, x, test_author)),
        allmkps
    )

    N = length(common_mkps)

    markups = Vector{NTuple{2, MarkPart}}(undef, N)
    @showprogress "Чтение разметки..." for (i, fn) in enumerate(common_mkps)
        ref_mkp = JSON3.read(fullpath(fullpath(markpath, fn, ref_author), fn, "json"), MarkPart)
        test_mkp = JSON3.read(fullpath(fullpath(markpath, fn, test_author), fn, "json"), MarkPart)
        ref_mkp.fs = test_mkp.fs = readheader(fullpath(binpath, fn, "hdr")).fs
        markups[i] = ref_mkp, test_mkp
    end

    return common_mkps, markups
end
