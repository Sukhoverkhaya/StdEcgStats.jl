# skv: использование встроенного метода eval для разрешения выражения из строки типа
# "true | false && true &!(false | true)" занимает слишком много времени, поэтому добавлю
# калькулятор логических операций

# skv: за основу взят https://github.com/IncartDev/std-ecg-report/blob/main/std-ecg-report/_libs/Calculators/Logic_calculator_gpt.h

# перевод символа оператора в элемент енума
const OPERATORS = Dict{String, Function}(
    "|" => |,
    "&" => &,
    "!" => !,
)

# разрешить оператор из текста в функцию
resolve(operator::AbstractString) = OPERATORS[operator]

# проверка приоритета опрератора
@enum Priority begin
    _or_ = 1
    _and_
    _not_
end

const PRECEDENCE = Dict{String, Priority}(
    "|" => _or_,
    "&" => _and_,
    "!" => _not_
)

# получить приоритет оператора
precedence(operator::AbstractString) = Int(get(PRECEDENCE, operator, 0))

# проверка, является оператор бинарным или унарным
isbinary(operator::Function) = operator in (|, &)

# "схлопнуть" выражение: последовательно применить операторы (сложить часть выражения в результат)
function collapse!(operands::Vector{Bool}, operators::Vector{<:AbstractString})
    operator = last(operators) |> resolve
    pop!(operators)

    if isbinary(operator) # применение бинарного оператора
        right = last(operands); pop!(operands)
        left = last(operands); pop!(operands)
        push!(operands, operator(left, right))
    else # применение унарного оператора
        right = last(operands); pop!(operands)
        push!(operands, operator(right))
    end
end

is_operator(x::AbstractString) = x in keys(OPERATORS)
is_operand(x::AbstractString) = x in ("true", "false")
is_left_bracket(x::AbstractString) = x == "("
is_right_bracket(x::AbstractString) = x == ")"
is_bracket(x::AbstractString) = x in ("(", ")")

# разрешение выражения
function eval_logical_expression(elements::Vector{<:AbstractString})
    
    operands = Vector{Bool}(undef, 0)
    operators = Vector{AbstractString}(undef, 0)

    for el in elements
        if is_operand(el) # встретили операнд
            push!(operands, parse(Bool, el))
        elseif is_operator(el) # встретили оператор
            while !isempty(operators) && (precedence(last(operators)) >= precedence(el)) # схлопываем часть выражения с операторами большего или равного встретившемуся приоритета
                collapse!(operands, operators)
            end
            push!(operators, el)
        elseif is_left_bracket(el) # встретили "("
            push!(operators, el)
        elseif is_right_bracket(el) # встретили ")"
            while !is_left_bracket(last(operators)) # схлопываем выражение в скобках
                collapse!(operands, operators)
            end
            pop!(operators)
        else # встерили неизвестный символ
            error("Unsupported character in logical expression!")
        end
    end

    while !isempty(operators) # схлопываем выражение
        collapse!(operands, operators)
    end

    return last(operands)
end


# ####
# const BRACKETS = ["(", ")"]
# const EMPTIES = [" ", "\n"]
# const RESERVED = [keys(OPERATORS)..., BRACKETS..., EMPTIES...]




# ### тесты

# exp = "true & false & !(true | false) | !false"

# operand2bool = x -> x

# @time begin
#     reserved = join("\\".*[keys(OPERATORS)..., "(", ")"], '|')
#     reg = Regex("(?:(?:(?<=($reserved))(?:))|(?:(?:)(?=($reserved))))")
#     elements = filter(!isempty, split(exp, reg, keepempty = false) .|> strip)
#     for i in eachindex(elements)
#         if !(elements[i] in RESERVED)
#             elements[i] = operand2bool(elements[i]) |> string
#         end
#     end
# end

# @time r1 = eval_logical_expression(elements);
# @time r2 = eval(Meta.parse(exp));

# # r1 == r2

# @time [eval_logical_expression(elements) for _ in 1:50];
# @time [eval(Meta.parse(exp)) for _ in 1:50];

# # test_exp = [
# #     "!(true & false) | (false & true) & !(true | false) & !true",
# #     "true & !(false | true) | (false & true) & !(true & false) & true",
# #     "!(false & true) | (true & false) & !(true | false) | false",
# #     "true & (false | !(true & false)) | !(false & true) & !true",
# #     "!(true | false) & (false | true) | !(true & false) & true",
# #     "false & !(true | false) | (true & false) & !(false & true)",
# #     "!(false & !(true | false)) | (true & false) & !true",
# #     "!(true & false) | ((false & true) | !(true | false)) & true",
# #     "true & (false | !(true & false)) | !(false & true) & !false",
# #     "!(false | true) & (true | !(false & true)) | !true"
# # ]

# # for exp in test_exp
# #     reserved = join("\\".*RESERVED, '|')
# #     reg = Regex("(?:(?:(?<=($reserved))(?:))|(?:(?:)(?=($reserved))))")
# #     elements = filter(x -> !(x in EMPTIES), split(exp, reg, keepempty = false))
# #     for i in eachindex(elements)
# #         if !(elements[i] in RESERVED)
# #             elements[i] = operand2bool(elements[i]) |> string
# #         end
# #     end

# #     r1 = eval_logical_expression(elements);
# #     r2 = eval(Meta.parse(exp));

# #     @info (r1 == r2) ? "ok" : "ERROR"
# # end
