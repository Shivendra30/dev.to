require "rails_helper"

RSpec.describe Follow, type: :model do
  let(:user) { create(:user) }
  let(:user_2) { create(:user) }

  describe "validations" do
    subject { user.follow(user_2) }

    it { is_expected.to validate_inclusion_of(:subscription_status).in_array(%w[all_articles none]) }

    # rubocop:disable RSpec/NamedSubject
    it {
      expect(subject).to validate_uniqueness_of(:followable_id).scoped_to(%i[followable_type follower_id follower_type])
    }
    # rubocop:enable RSpec/NamedSubject
  end

  it "follows user" do
    user.follow(user_2)
    expect(user.following?(user_2)).to eq(true)
  end

  context "when enqueuing jobs" do
    it "enqueues create channel job" do
      expect do
        described_class.create(follower: user, followable: user_2)
      end.to change(Follows::CreateChatChannelWorker.jobs, :size).by(1)
    end

    it "enqueues send notification worker" do
      expect do
        described_class.create(follower: user, followable: user_2)
      end.to change(Follows::SendEmailNotificationWorker.jobs, :size).by(1)
    end
  end

  context "when creating and inline" do
    it "touches the follower user while creating" do
      timestamp = 1.day.ago
      user.update_columns(updated_at: timestamp, last_followed_at: timestamp)
      described_class.create!(follower: user, followable: user_2)

      user.reload
      expect(user.updated_at).to be > timestamp
      expect(user.last_followed_at).to be > timestamp
    end

    it "doesn't create a channel when a followable is an org" do
      expect do
        sidekiq_perform_enqueued_jobs do
          described_class.create!(follower: user, followable: create(:organization))
        end
      end.not_to change(ChatChannel, :count)
    end

    it "doesn't create a chat channel when users don't follow mutually" do
      expect do
        sidekiq_perform_enqueued_jobs do
          described_class.create!(follower: user, followable: user_2)
        end
      end.not_to change(ChatChannel, :count)
    end

    it "creates a chat channel when users follow mutually" do
      described_class.create!(follower: user_2, followable: user)
      expect do
        sidekiq_perform_enqueued_jobs do
          described_class.create!(follower: user, followable: user_2)
        end
      end.to change(ChatChannel, :count).by(1)
    end

    it "sends an email notification" do
      user_2.update_column(:email_follower_notifications, true)
      expect do
        Sidekiq::Testing.inline! do
          described_class.create!(follower: user, followable: user_2)
        end
      end.to change(EmailMessage, :count).by(1)
    end
  end
end
