require 'parslet'

module CParser
  #
  # The ANSI C Parser using the
  # [Parslet](http://kschiess.github.com/parslet/) library.
  #
  # ANSI C Grammar:
  #
  # * http://www.lysator.liu.se/c/ANSI-C-grammar-l.html
  # * http://www.lysator.liu.se/c/ANSI-C-grammar-y.html
  #
  class Parser < Parslet::Parser

    rule(:new_line) { match('[\n\r]').repeat(1) }

    rule(:space) { match('[ \t\v\n\f]') }
    rule(:spaces) { space.repeat(1) }
    rule(:space?) { space.maybe }
    rule(:spaces?) { space.repeat }

    rule(:digit) { match('[0-9]') }
    rule(:digits) { digit.repeat(1) }
    rule(:digits?) { digit.repeat }

    rule(:alpha) { match('[a-zA-Z_]') }
    rule(:xdigit) { digit | match('[a-fA-F]') }

    rule(:e) { match('[eE]') >> match('[+-]').maybe >> digit.repeat(1) }
    rule(:float_size) { match('[fFlL]') }
    rule(:int_size) { match('[uUlL]').repeat }

    rule(:e?) { e.maybe }
    rule(:float_size?) { float_size.maybe }
    rule(:int_size?) { int_size.maybe }

    rule(:comment) {
      (str('/*') >> (str('*/').absnt? >> any).repeat >> str('*/')) |
      (str('//') >> (new_line.absnt? >> any).repeat >> new_line)
    }

    def self.keywords(*names)
      names.each do |name|
        rule("#{name}_keyword") { str(name.to_s).as(:keyword) >> spaces? }
      end
    end

    keywords :auto, :break, :case, :char, :const, :continue, :default, :do,
      :double, :else, :enum, :extern, :float, :for, :goto, :if, :int,
      :long, :register, :return, :short, :signed, :sizeof, :static,
      :struct, :switch, :typedef, :union, :unsigned, :void, :volatile,
      :while

    rule(:identifier) {
      (alpha >> (alpha | digit).repeat).as(:identifier) >> spaces?
    }

    rule(:hex_constant) {
      (match('0[xX]') >> xdigit.repeat(1) >> int_size?).as(:hex) >> spaces?
    }
    rule(:octal_constant) {
      (str('0') >> digits >> int_size?).as(:octal) >> spaces?
    }
    rule(:decimal_constant) {
      (digits >> int_size.maybe).as(:decimal) >> spaces?
    }
    rule(:string_constant) {
      (
        str('L').maybe >> str("'") >>
        (match("\\.") | match("[^\\']")).repeat(1) >>
        str("'")
      ).as(:string) >> spaces?
    }

    rule(:float_constant) {
      (
        (digits >> e >> float_size?) |
        (digits? >> str('.') >> digits >> e? >> float_size?) |
        (digits >> str('.') >> digits? >> e? >> float_size?)
      ).as(:float) >> spaces?
    }

    rule(:constant) {
      hex_constant |
      octal_constant |
      decimal_constant |
      float_constant |
      string_constant
    }

    rule(:string_literal) {
      (
        str('L').maybe >> str('"') >>
        (match("\\.") | match('[^\\"]')).repeat >>
        str('"')
      ).as(:string) >> spaces?
    }

    def self.symbols(symbols)
      symbols.each do |name,symbol|
        rule(name) { str(symbol) >> spaces? }
      end
    end

    symbols :ellipsis => '...',
            :semicolon => ';',
            :comma => ',',
            :colon => ':',
            :left_paren => '(',
            :right_paren => ')',
            :member_access => '.',
            :question_mark => '?'

    rule(:left_brace) { (str('{') | str('<%')) >> spaces? }
    rule(:right_brace) { (str('}') | str('%>')) >> spaces? }

    rule(:left_bracket) { (str('[') | str('<:')) >> spaces? }
    rule(:right_bracket) { (str(']') | str(':>')) >> spaces? }

    def self.operators(operators={})
      trailing_chars = Hash.new { |hash,symbol| hash[symbol] = [] }

      operators.each_value do |symbol|
        operators.each_value do |op|
          if op[0,symbol.length] == symbol
            char = op[symbol.length,1]

            unless (char.nil? || char.empty?)
              trailing_chars[symbol] << char
            end
          end
        end
      end

      operators.each do |name,symbol|
        trailing = trailing_chars[symbol]

        if trailing.empty?
          rule(name) { str(symbol).as(:operator) >> spaces? }
        else
          pattern = "[#{Regexp.escape(trailing.join)}]"

          rule(name) {
            (str(symbol) >> match(pattern).absnt?).as(:operator) >> spaces?
          }
        end
      end
    end

    operators :right_shift_assign => '>>=',
              :left_shift_assign => '<<=',
              :add_assign => '+=',
              :subtract_assign => '-=',
              :multiply_assign => '*=',
              :divide_assign => '/=',
              :modulus_assign => '%=',
              :binary_and_assign => '&=',
              :xor_assign => '^=',
              :binary_or_assign => '|=',
              :inc => '++',
              :dec => '--',
              :pointer_access => '->',
              :logical_and => '&&',
              :logical_or => '||',
              :less_equal => '<=',
              :greater_equal => '>=',
              :equal => '==',
              :not_equal => '!=',
              :assign => '=',
              :add => '+',
              :subtract => '-',
              :multiply => '*',
              :divide => '/',
              :modulus => '%',
              :less => '<',
              :greater => '>',
              :negate => '!',
              :binary_or => '|',
              :binary_and => '&',
              :xor => '^',
              :left_shift => '<<',
              :right_shift => '>>',
              :inverse => '~'

    rule(:primary_expression) {
      (identifier | constant | string_literal) |
      (left_paren >> expression >> right_paren)
    }

    rule(:postfix_expression) {
      primary_expression >> (
        (left_bracket >> expression >> right_bracket) |
        (left_paren >> argument_expression_list.maybe >> right_paren) |
        ((member_access | pointer_access) >> identifier) |
        inc | dec
      ).repeat
    }

    rule(:argument_expression_list) {
      (assignment_expression >> comma >> argument_expression_list) |
      assignment_expression
    }

    rule(:sizeof_expression) {
      sizeof_keyword >> (
        (unary_expression.as(:expr)) |
        (left_paren >> type_name.as(:type) >> right_paren)
      )
    }

    rule(:unary_expression) {
      sizeof_expression.as(:sizeof) |
      postfix_expression |
      (inc >> unary_expression).as(:inc) |
      (dec >> unary_expression).as(:dec) |
      (unary_operator >> cast_expression).as(:unary)
    }

    rule(:unary_operator) {
      (binary_and | multiply | add | subtract | inverse | negate)
    }

    rule(:cast_expression) {
      (
        left_paren >> type_name.as(:type) >> right_paren >>
        cast_expression
      ).as(:cast) | unary_expression
    }

    rule(:multiplicative_expression) {
      (
        cast_expression.as(:left) >>
        (multiply | divide | modulus) >>
        multiplicative_expression.as(:right)
      ).as(:multiplicative) | cast_expression
    }

    rule(:additive_expression) {
      (
        multiplicative_expression.as(:left) >>
        (add | subtract) >>
        additive_expression.as(:right)
      ).as(:additive) | multiplicative_expression
    }

    rule(:shift_expression) {
      (
        additive_expression.as(:left) >>
        (left_shift | right_shift) >>
        shift_expression.as(:right)
      ).as(:shift) | additive_expression
    }

    rule(:relational_expression) {
      (
        shift_expression.as(:left) >>
        (less | greater | less_equal | greater_equal) >>
        relational_expression.as(:right)
      ).as(:relational) | shift_expression
    }

    rule(:equality_expression) {
      (
        relational_expression.as(:left) >>
        (equal | not_equal) >>
        equality_expression.as(:right)
      ).as(:equality) | relational_expression
    }

    rule(:and_expression) {
      (
        equality_expression.as(:left) >>
        binary_and >>
        and_expression.as(:right)
      ).as(:binary_and) | equality_expression
    }

    rule(:exclusive_or_expression) {
      (
        and_expression.as(:left) >>
        xor >>
        exclusive_or_expression.as(:right)
      ).as(:xor) | and_expression
    }

    rule(:inclusive_or_expression) {
      (
        exclusive_or_expression.as(:left) >>
        binary_or >>
        inclusive_or_expression.as(:right)
      ).as(:binary_or) | exclusive_or_expression
    }

    rule(:logical_and_expression) {
      (
        inclusive_or_expression.as(:left) >>
        logical_and >>
        logical_and_expression.as(:right)
      ).as(:logical_and) | inclusive_or_expression
    }

    rule(:logical_or_expression) {
      (
        logical_and_expression.as(:left) >>
        logical_or >>
        logical_or_expression.as(:right)
      ).as(:logical_or) | logical_and_expression
    }

    rule(:conditional_expression) {
      (
        logical_or_expression.as(:condition) >> question_mark >>
        expression.as(:true) >> colon >>
        conditional_expression.as(:false)
      ).as(:conditional) | logical_or_expression
    }

    rule(:assignment_expression) {
      (
        unary_expression.as(:left) >>
        assignment_operator >>
        assignment_expression.as(:right)
      ).as(:assign) | conditional_expression
    }

    rule(:assignment_operator) {
      assign |
      multiply_assign |
      divide_assign |
      modulus_assign |
      add_assign |
      subtract_assign |
      left_shift_assign |
      right_shift_assign |
      binary_and_assign |
      xor_assign |
      binary_or_assign
    }

    rule(:expression) {
      assignment_expression >> (comma >> assignment_expression).repeat
    }
    rule(:expression?) { expression.maybe }

    rule(:constant_expression) { conditional_expression }
    rule(:constant_expression?) { constant_expression.maybe }

    rule(:declaration) {
      declaration_specifiers >> init_declarator_list.maybe >> semicolon
    }

    rule(:declaration_specifiers) {
      (
        storage_class_specifier.as(:specifier) |
        type_specifier.as(:type) |
        type_qualifier.as(:qualifier)
      ).repeat(1)
    }

    rule(:init_declarator_list) {
      init_declarator >> (comma >> init_declarator).repeat
    }

    rule(:init_declarator) {
      declarator >> (assign >> initializer).maybe
    }

    rule(:storage_class_specifier) {
      typedef_keyword |
      extern_keyword |
      static_keyword |
      auto_keyword |
      register_keyword
    }

    rule(:type_specifier) {
      void_keyword |
      char_keyword |
      short_keyword |
      int_keyword |
      long_keyword |
      float_keyword |
      double_keyword |
      signed_keyword |
      unsigned_keyword |
      struct_or_union_specifier |
      enum_specifier
    }

    rule(:struct_or_union_specifier) {
      struct_or_union >> (
        (
          identifier.maybe >>
          (left_brace >> struct_declaration_list >> right_brace)
        ) | identifier
      )
    }

    rule(:struct_or_union) { struct_keyword | union_keyword }

    rule(:struct_declaration_list) { struct_declaration.repeat(1) }

    rule(:struct_declaration) {
      specifier_qualifier_list >> struct_declarator_list >> semicolon
    }

    rule(:specifier_qualifier_list) {
      (type_specifier | type_qualifier).repeat(1)
    }

    rule(:struct_declarator_list) {
      struct_declarator >> (comma >> struct_declarator).repeat
    }

    rule(:struct_declarator) {
      (declarator.maybe >> (colon >> constant_expression)) |
      declarator
    }

    rule(:enum_specifier) {
      enum_keyword >> (
        (
          identifier.maybe >> (left_brace >> enumerator_list >> right_brace)
        ) | identifier
      )
    }

    rule(:enumerator_list) {
      enumerator >> (comma >> enumerator).repeat
    }

    rule(:enumerator) {
      identifier >> (assign >> constant_expression).maybe
    }

    rule(:type_qualifier) { const_keyword | volatile_keyword }

    rule(:declarator) { pointer? >> direct_declarator }

    rule(:direct_declarator) {
      (identifier | (left_paren >> declarator >> right_paren)) >>
      (
        (
          left_bracket >>
          constant_expression.maybe.as(:size) >>
          right_bracket
        ).as(:array) | (
          left_paren >>
          (parameter_type_list | identifier_list).maybe >>
          right_paren
        )
      ).repeat
    }

    rule(:pointer) {
      multiply >> (multiply | type_qualifier_list).repeat
    }
    rule(:pointer?) { pointer.maybe }

    rule(:type_qualifier_list) { type_qualifier.repeat(1) }

    rule(:parameter_type_list) {
      parameter_list >> (comma >> ellipsis).maybe
    }
    rule(:parameter_type_list?) { parameter_type_list.maybe }

    rule(:parameter_list) {
      parameter_declaration >> (comma >> parameter_declaration).repeat
    }

    rule(:parameter_declaration) {
      declaration_specifiers >> (declarator | abstract_declarator).maybe
    }

    rule(:identifier_list) {
      identifier >> (comma >> identifier).repeat
    }

    rule(:type_name) {
      specifier_qualifier_list >> abstract_declarator.maybe
    }

    rule(:abstract_declarator) {
      (pointer? >> direct_abstract_declarator) | pointer
    }

    rule(:direct_abstract_declarator) {
      (
        (left_paren >> abstract_declarator >> right_paren) |
        (left_bracket >> constant_expression? >> right_bracket) |
        (left_paren >> parameter_type_list? >> right_paren)
      ) >> (
        (left_bracket >> constant_expression? >> right_bracket) |
        (left_paren >> parameter_type_list? >> right_paren)
      ).repeat
    }

    rule(:initializer) {
      assignment_expression |
      (left_brace >> initializer_list >> comma.maybe >> right_brace)
    }

    rule(:initializer_list) {
      initializer >> (comma >> initializer).repeat
    }

    rule(:statement) {
      labeled_statement |
      compound_statement |
      expression_statement |
      selection_statement |
      iteration_statement |
      jump_statement
    }

    rule(:label_statement) {
      (identifier | default_keyword).as(:name) >> colon >>
      statement.as(:body)
    }

    rule(:case_statement) {
      case_keyword >> constant_expression.as(:key) >> colon >>
      statement.as(:body)
    }

    rule(:labeled_statement) {
      label_statement.as(:label) | case_statement.as(:case)
    }

    rule(:compound_statement) {
      left_brace >>
      declaration_list.maybe.as(:declarations) >> statement_list.maybe >>
      right_brace
    }

    rule(:declaration_list) { declaration.repeat(1) }

    rule(:statement_list) { statement.repeat(1) }

    rule(:expression_statement) { expression? >> semicolon }

    rule(:if_statement) {
      if_keyword >>
      left_paren >> expression.as(:condition) >> right_paren >>
      statement.as(:body) >>
      (else_keyword >> statement.as(:else)).maybe
    }

    rule(:switch_statement) {
      switch_keyword >>
      left_paren >> expression.as(:expression) >> right_paren >>
      statement.as(:body)
    }

    rule(:selection_statement) {
      if_statement.as(:if) | switch_statement.as(:switch)
    }

    rule(:while_statement) {
      while_keyword >>
      left_paren >> expression.as(:condition) >> right_paren >>
      statement.as(:body)
    }

    rule(:do_while_statement) {
      do_keyword >> statement.as(:body) >> while_keyword >>
      left_paren >> expression.as(:condition) >> right_paren >> semicolon
    }

    rule(:for_statement) {
      for_keyword >> left_paren >>
      expression_statement.as(:initializer) >>
      expression_statement.as(:condition) >>
      expression.maybe.as(:update) >>
      right_paren >>
      statement.as(:body)
    }

    rule(:iteration_statement) {
      while_statement.as(:while) |
      do_while_statement.as(:do_while) |
      for_statement.as(:for)
    }

    rule(:jump_statement) {
      (
        (goto_keyword >> identifier.as(:goto)) |
        continue_keyword.as(:continue) |
        break_keyword.as(:break) |
        (return_keyword >> expression.maybe.as(:value)).as(:return)
      ) >> semicolon
    }

    rule(:translation_unit) { external_declaration.repeat(1) }

    rule(:external_declaration) {
      function_definition.as(:function) |
      declaration
    }

    rule(:function_definition) {
      declaration_specifiers.maybe >>
      declarator >>
      declaration_list.maybe >>
      compound_statement.as(:body)
    }

    root :translation_unit

  end
end
