module CompareSegments
### модуль сравнения сегментов AF VF
# сравнение по событиям и по длительности

import TimeSamplings as ts
using DataFrames, CSV


export segments_pairs, report_comparison

function report_comparison(filenames_list, se_pairs_list, sp_pairs_list, duration_pairs_list, outfile)
    df = report_comparison(filenames_list, se_pairs_list, sp_pairs_list, duration_pairs_list)
    CSV.write(outfile, df)
end

# получение суммарной таблицы статистики
function report_comparison(filenames_list, se_pairs_list, sp_pairs_list, duration_pairs_list)

    counts = segments_counts.(se_pairs_list, sp_pairs_list, duration_pairs_list)
    rows = segments_accuracy.(counts)

    counts_gross = reduce((x,y) -> x .+ y, counts)
    row_gross = segments_accuracy(counts_gross)

    df = DataFrame([rows..., row_gross])
    insertcols!(df, 1, :File => [filenames_list..., "GROSS"])

    return df
end

function segments_accuracy(counts)
    TPs, FN, TPp, FP, DurRef, DurTest, DurOverlapped = counts
    ESe = round(TPs/(TPs+FN)*100, sigdigits = 4)
    EPp = round(TPp/(TPp+FP)*100, sigdigits = 4)
    DSe = round(DurOverlapped / DurRef*100, sigdigits = 4)
    DPp = round(DurOverlapped / DurTest*100, sigdigits = 4)

    return (; TPs, FN, TPp, FP, ESe, EPp, DSe, DPp, DurRef, DurTest, DurOverlapped)
end

function segments_counts(se_pairs, sp_pairs, duration_pairs)
    (episode_counts(se_pairs, sp_pairs)..., duration_counts(duration_pairs)...)
end

function episode_counts(se_pairs, sp_pairs)
    TPs = FN = TPp = FP = 0
    for (seg, type) in se_pairs
        if type
            TPs += 1
        else
            FN += 1
        end
    end
    for (seg, type) in sp_pairs
        if type
            TPp += 1
        else
            FP += 1
        end
    end
    return TPs, FN, TPp, FP
end

function duration_counts(duration_pairs)
    TP = FN = FP = 0
    for (seg, is_r, is_t) in duration_pairs
        if is_r && is_t
            TP += length(seg)
        elseif is_r && !is_t
            FN += length(seg)
        elseif !is_r && is_t
            FP += length(seg)
        end
    end
    DurRef = TP + FN
    DurTest = TP + FP
    DurOverlapped = TP
    return DurRef, DurTest, DurOverlapped
end

# подается на вход битовые массивы сегментов
function segments_pairs(
    pos_ref::AbstractVector{Int},
    is_ref::AbstractVector{Bool},
    pos_test::AbstractVector{Int},
    is_test::AbstractVector{Bool},
    radius::Int = 0)

    # сегменты индексов позиций
    iseg_ref = ts.bitvec2seg(is_ref)
    iseg_test = ts.bitvec2seg(is_test)

    # сегменты позиий
    seg_ref = map(iseg_ref) do iseg
        pos_ref[first(iseg)] : pos_ref[last(iseg)]
    end
    seg_test = map(iseg_test) do iseg
        pos_test[first(iseg)] : pos_test[last(iseg)]
    end

    # определим все пары пересечений c учетом радиуса
    ipairs = ts.seg_outerjoin_indexpairs(seg_ref, seg_test, radius)
    Np = length(ipairs)

    # 1) сравнение по эпизодам

    # реф. сегмент, наличие пересечения
    se_pairs = Tuple{UnitRange{Int}, Bool}[] # пары по чувствительности

    # тест сегмент, наличие пересечения
    sp_pairs = Tuple{UnitRange{Int}, Bool}[] # пары по специфичности

    ir_last = it_last = 0
    for (ir, it) in ipairs
        if ir != ir_last && ir > 0
            seg_type = it > 0 # true - есть пересечение, false - нет
            push!(se_pairs, (seg_ref[ir], seg_type))
            ir_last = ir
        end
        if it != it_last && it > 0
            seg_type = ir > 0 # true - есть пересечение, false - нет
            push!(se_pairs, (seg_test[it], seg_type))
            it_last = it
        end
    end

    # 2) сравнение по длительностям

    duration_pairs = Tuple{UnitRange{Int}, Bool, Bool}[]
    seg_r = seg_t = 0:-1 #
    last_end = 0 # позиция уже обработанного участка
    for (ir, it) in ipairs
        is_r = ir > 0
        is_t = it > 0

        # переводим пары - в сегменты с типами пересечений
        # !is_r && !is_t  0-0 не бывает
        if is_r && !is_t # 1-0
            seg = seg_r
            push!(duration_pairs, (seg_ref[ir], true, false))
            last_end = last(seg_r)

        elseif !is_r && is_t # 0-1
            seg = seg_t
            push!(duration_pairs, (seg_test[it], false, true))
            last_end = last(seg_t)

        elseif is_r && is_t # 1-1

            # обрежем возможные повторные пересечения в начале
            seg_r = seg_ref[ir]
            seg_r = max(last_end+1, first(seg_r)) : last(seg_r)

            seg_t = seg_test[it]
            seg_t = max(last_end+1, first(seg_t)) : last(seg_t)

            last_end = min(last(seg_r), last(seg_t)) # минимальный из обоих

            # до пересечения
            if first(seg_r) < first(seg_t) # 1-0 - более ранний seg_r в паре
                seg = first(seg_r) : first(seg_t)-1
                push!(duration_pairs, (seg, true, false))
            elseif first(seg_t) < first(seg_r)  # 0-1 - более ранний seg_t в паре
                seg = first(seg_t) : first(seg_r)-1
                push!(duration_pairs, (seg, false, true))
            end

            # перечение
            seg = intersect(seg_r, seg_t)
            push!(duration_pairs, (seg, true, true))

            # после пересечения - остаавляем для следующей итерации, т.к. мб ещё одна пара с текущим
        end

    end
    # для случая, если последня итерация не захватила участок после пересечения
    if last(seg_r) > last_end # 1-0 - более поздний seg_r в паре
        seg = last_end+1 : last(seg_r)
        push!(duration_pairs, (seg, true, false))
    elseif last(seg_t) > last_end # 0-1 - более поздний seg_t в паре
        seg = last_end+1 : last(seg_t)
        push!(duration_pairs, (seg, false, true))
    end

    return se_pairs, sp_pairs, duration_pairs
end

end

#=
# ! длительности в точках, для отчета перевести в формат времени
se_pairs, sp_pairs, duration_pairs = CompareSegments.segments_pairs(
    [100, 200, 300], [false, true, true],
    [50, 150, 210, 295], [false, true, true, true]
)

file_list = ["file1", "file2"]
se_pairs_list = [se_pairs, se_pairs]
sp_pairs_list = [sp_pairs, sp_pairs]
duration_pairs_list = [duration_pairs, duration_pairs]

CompareSegments.report_comparison(file_list, se_pairs_list, sp_pairs_list, duration_pairs_list)
=#
