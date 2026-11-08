# Stands in for the LLM: no network, and the same text always gets the same proposals, so specs and
# local runs are reproducible. Answers each schema property with a value and the text's first sentence
# as excerpt, the way the real extractor quotes the narrative; about one field in five is "not stated"
# (null, empty excerpt), so that answer is exercised too.
class Llm::FakeExtractor
  def provider
    "fake"
  end

  def model
    "fake-extractor"
  end

  def prompt_version
    "fake-v1"
  end

  def extract(text:, schema:)
    excerpt = text.to_s.strip[/\A[^.!?\n]*[.!?]?/]
    schema.fetch("properties").to_h do |code, property|
      value_schema = property.dig("properties", "value")
      if value_schema.key?("anyOf") && seed(text, "#{code}:stated") % 5 == 0
        [ code, { "value" => nil, "excerpt" => "" } ]
      else
        stated = value_schema.fetch("anyOf", [ value_schema ]).find { |option| option["type"] != "null" }
        [ code, { "value" => value_for(text, code, stated), "excerpt" => excerpt } ]
      end
    end
  end

  private
    def value_for(text, code, schema)
      if schema["enum"]
        pick(text, code, schema["enum"])
      elsif schema["type"] == "array"
        [ pick(text, code, schema.dig("items", "enum")) ]
      elsif schema["type"] == "integer"
        seed(text, code) % 10
      end
    end

    def pick(text, code, choices)
      choices[seed(text, code) % choices.size]
    end

    def seed(text, code)
      Digest::SHA256.hexdigest("#{code}:#{text}").to_i(16)
    end
end
