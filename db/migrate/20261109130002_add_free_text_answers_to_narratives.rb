class AddFreeTextAnswersToNarratives < ActiveRecord::Migration[8.1]
  def change
    add_column :narratives, :free_text_answers, :text
  end
end
