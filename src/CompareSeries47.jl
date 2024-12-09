module CompareSeries47
# сюда перенесены функции сравнения серий по ГОСТ-47, чтобы не тащить пакет AlgCompare
# придется изменить функцию так, чтобы получать пары ошибок, которые участвуют в статистике

import TimeSamplings as ts
using DataFrames, CSV

export series_pairs, report_comparison

function report_comparison(filenames_list, se_pairs_list, sp_pairs_list, outfile)
    df = report_comparison(filenames_list, se_pairs_list, sp_pairs_list)
    CSV.write(outfile, df)
end

# получение суммарной таблицы статистики
function report_comparison(filenames_list, se_pairs_list, sp_pairs_list)
    MSe_list = series_matrix.(se_pairs_list)
    MPp_list = series_matrix.(sp_pairs_list)
    rows = series_accuracy.(MSe_list, MPp_list) ## считаем точность

    MSe_gross = sum(MSe_list)
    MPp_gross = sum(MPp_list)
    row_gross = series_accuracy(MSe_gross, MPp_gross) ## считаем точность

    df = DataFrame([rows..., row_gross])
    insertcols!(df, 1, :File => [filenames_list..., "GROSS"])

    return df
end

# пока эту функцию заменил суммарный отчет report_comparison
# аналог AlgCompare.Series.compare_file
# подадим только метки наличия и отсутствия серии (этим отличается от AlgCompare)
# function compare_series(
#     pos_ref::AbstractVector{Int},
#     is_ref::AbstractVector{Bool},
#     pos_test::AbstractVector{Int},
#     is_test::AbstractVector{Bool},
#     radius = 0) # round(Int, radius_ms / 1000 * freq)

#     se_pairs, sp_pairs = series_pairs(pos_ref, is_ref, pos_test, is_test, radius)
#     MSe = series_matrix(se_pairs)
#     MPp = series_matrix(sp_pairs)

#     table = series_accuracy(MSe, MPp) ## считаем точность
#     return table, (se_pairs, sp_pairs)
# end

# расчет пар событий серий для матриц чувствительности и специфичности:
# se_pairs = TPs и FN
# sp_pairs = TPp и FP
function series_pairs(
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

    # реф. сегмент, длина реф, длина тест
    se_pairs = Tuple{UnitRange{Int}, Int, Int}[] # пары по чувствительности

    # тест сегмент, длина реф, длина тест
    sp_pairs = Tuple{UnitRange{Int}, Int, Int}[] # пары по специфичности

    ir_curr = it_curr = 0 # индекс текущего сравниваемого
    it_max = ir_max = 0 # индекс максимального по длине второго сравниваемого
    tlen_max = rlen_max = 0
    for (ir, it) in ipairs

        # 1) отберем пары по чувствительности (s) = цикл по референтным
        # пересечение с текущим сегментом
        if ir_curr === ir
            # выберем максимальный по длине из пересекшихся
            if it > 0 && length(iseg_test[it]) > tlen_max
                it_max = it
                tlen_max = length(iseg_test[it])
            end

        else # if ir_curr !== ir # || iip == Np ?
            # запишем: реф. сегмент, длина реф, длина тест
            if ir_curr > 0
                rseg = seg_ref[ir_curr]
                rlen = length(iseg_ref[ir_curr])
                rseg_d = first(rseg) - radius : last(rseg) + radius # окно подбора реф. сегмента

                tlen = 0
                # обнаружим кол-во событий в test, которые пересекаются с ref
                if it_max > 0
                    for j in iseg_test[it_max] # по всем позициям внутри выбранного сегмента
                        if first(rseg_d) <= pos_test[j] <= last(rseg_d) # pos_test[j] in rseg_d
                            tlen += 1
                        end
                    end
                end

                push!(se_pairs, (rseg_d, rlen, tlen))
            end

            # итерация
            ir_curr = ir
            it_max = it
            tlen_max = it > 0 ? length(iseg_test[it]) : 0
        end

        # 1) отберем пары по специфичности (p) = цикл по тестовым
        # пересечение с текущим сегментом
        if it_curr === it
            # выберем максимальный по длине из пересекшихся
            if ir > 0 && length(iseg_ref[ir]) > rlen_max
                ir_max = ir
                rlen_max = length(iseg_ref[ir])
            end

        else # if ir_curr !== ir # || iip == Np ?
            # запишем: реф. сегмент, длина реф, длина тест
            if it_curr > 0
                tseg = seg_test[it_curr]
                tlen = length(iseg_test[it_curr])
                tseg_d = first(tseg) - radius : last(tseg) + radius # окно подбора реф. сегмента

                rlen = 0
                # обнаружим кол-во событий в test, которые пересекаются с ref
                if ir_max > 0
                    for j in iseg_ref[ir_max] # по всем позициям внутри выбранного сегмента
                        if first(tseg_d) <= pos_ref[j] <= last(tseg_d) # pos_test[j] in rseg_d
                            rlen += 1
                        end
                    end
                end

                push!(sp_pairs, (tseg_d, rlen, tlen))
            end

            # итерация
            it_curr = it
            ir_max = ir
            rlen_max = ir > 0 ? length(iseg_ref[ir]) : 0
        end

    end

    return se_pairs, sp_pairs
end

# Расчет кроссматрицы по длинам серий: 0,1,2,3,4,5,6+
# ВХОД:
# series_pairs - пары событий с длинами серий
# ВЫХОД:
# MS - кроссматрица длин серий
function series_matrix(series_pairs)
    MS = zeros(Int,7,7)
    for (seg, rlen, tlen) in series_pairs
        k1 = min(6, rlen) + 1 # 1-based index
        k2 = min(6, tlen) + 1
        MS[k1,k2] = MS[k1,k2] + 1
    end
    return MS
end

# интерпретация пар сегментов - в типы ошибок:
# CTPs, CFN | CTPp, CFP
# STPs, SFN | STPp, SFP
# LTPs, LFN | LTPp, LFP
function pairs_len2err(se_pairs, sp_pairs)

    se_errs = map(se_pairs) do (seg, rlen, tlen)
        err = if rlen == 2   && tlen in 2:6; :CTPs
        elseif   rlen in 3:5 && tlen in 3:6; :STPs
        elseif   rlen >= 6   && tlen >= 6  ; :LTPs

        elseif   rlen == 2   && tlen in 0:1; :CFN
        elseif   rlen in 3:5 && tlen in 0:2; :SFN
        elseif   rlen >= 6   && tlen in 0:5; :LFN
        else; :undef
        end
        return seg, err
    end

    sp_errs = map(sp_pairs) do (seg, rlen, tlen)
        err = if rlen in 2:6 && tlen == 2  ; :CTPp
        elseif   rlen in 3:6 && tlen in 3:5; :STPp
        elseif   rlen >= 6   && tlen >= 6  ; :LTPp

        elseif   rlen in 0:1 && tlen == 2  ; :CFP
        elseif   rlen in 0:2 && tlen in 3:5; :SFP
        elseif   rlen in 0:5 && tlen >= 6  ; :LFP
        else; :undef
        end
        return seg, err
    end

    return se_errs, sp_errs
end

# ВХОД:
# s, p - кроссматрицы 7x7 по длинам серий: 0,1,2,3,4,5,6+
# ВЫХОД:
# stats - набор статистик по ГОСТ-51
function series_accuracy(s, p)
    #s = S_table |> Array
    #p = P_table |> Array
    ## C - куплеты
    c_TPs = s[3, 3:7]
    c_FN  = s[3, 1:2]
    c_TPp = p[3:7, 3]
    c_FP  = p[1:2, 3]

    CTPs = sum(c_TPs)
    CFN  = sum(c_FN)
    CTPp = sum(c_TPp)
    CFP  = sum(c_FP)

    CSe = round(CTPs / (CTPs + CFN) * 100, digits = 1)
    CPp = round(CTPp / (CTPp + CFP) * 100, digits = 1)

    ## S - короткие серии
    s_TPs = s[4:6, 4:7]
    s_FN  = s[4:6, 1:3]
    s_TPp = p[4:7, 4:6]
    s_FP  = p[1:3, 4:6]

    STPs = sum(s_TPs)
    SFN  = sum(s_FN)
    STPp = sum(s_TPp)
    SFP  = sum(s_FP)

    SSe = round(STPs / (STPs + SFN) * 100, digits = 1)
    SPp = round(STPp / (STPp + SFP) * 100, digits = 1)

    ## L - длинные серии
    l_TPs = s[7, 7]
    l_FN  = s[7, 1:6]
    l_TPp = p[7, 7]
    l_FP  = p[1:6, 7]

    LTPs = sum(l_TPs)
    LFN  = sum(l_FN)
    LTPp = sum(l_TPp)
    LFP  = sum(l_FP)

    LSe = round(LTPs / (LTPs + LFN) * 100, digits = 1)
    LPp = round(LTPp / (LTPp + LFP) * 100, digits = 1)

    stats = (;
        CTPs, CFN, CTPp, CFP,
        STPs, SFN, STPp, SFP,
        LTPs, LFN, LTPp, LFP,
        CSe, CPp,
        SSe, SPp,
        LSe, LPp)

    return stats
end

end
