class AddSubjectAndDomainToEventEngineOutboxEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :event_engine_outbox_events, :subject, :string
    add_column :event_engine_outbox_events, :domain, :string
  end
end
