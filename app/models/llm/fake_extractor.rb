# Stands in for the LLM: no network, and the same text always gets the same proposals, so specs and
# local runs are reproducible. Answers each schema property with a value and the text's first sentence
# as excerpt, the way the real extractor quotes the narrative.
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
      [ code, { "value" => value_for(text, code, property.dig("properties", "value")), "excerpt" => excerpt } ]
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
