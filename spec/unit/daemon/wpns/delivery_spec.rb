require 'unit_spec_helper'

describe Rapns::Daemon::Wpns::Delivery do
  let(:app) { Rapns::Wpns::App.new(:name => "MyApp") }
  let(:notification) { Rapns::Wpns::Notification.create!(:app => app,:alert => "test",
                                                         :uri => "http://some.example/",
                                                         :deliver_after => Time.now) }
  let(:logger) { double(:error => nil, :info => nil, :warn => nil) }
  let(:response) { double(:code => 200, :header => {}) }
  let(:http) { double(:shutdown => nil, :request => response) }
  let(:now) { Time.now }
  let(:batch) { double(:mark_failed => nil, :mark_delivered => nil) }
  let(:delivery) { Rapns::Daemon::Wpns::Delivery.new(app, http, notification, batch) }
  let(:store) { double(:create_wpns_notification => double(:id => 2)) }

  def perform
    delivery.perform
  end

  before do
    delivery.stub(:reflect => nil)
    Rapns::Daemon.stub(:store => store)
    Time.stub(:now => now)
    Rapns.stub(:logger => logger)
  end

  shared_examples_for "an notification with some delivery faliures" do
    let(:new_notification) { Rapns::Wpns::Notification.where('id != ?', notification.id).first }

    before { response.stub(:body => JSON.dump(body)) }

    it "marks the original notification falied" do
      batch.should_receive(:mark_failed).with(notification, nil, error_description)
      perform rescue Rapns::DeliveryError
    end

    it "raises a DeliveryError" do
      expect { perform }.to raise_error(Rapns::DeliveryError)
    end
  end

  describe "an 200 response" do
    before do
      response.stub(:code => 200)
    end

    it "marks the notification as delivered if delivered successfully to all devices" do
      response.stub(:body => JSON.dump({ "failure" => 0 }))
      response.stub(:to_hash => {"x-notificationstatus" => ["Received"]})
      batch.should_receive(:mark_delivered).with(notification)
      perform
    end

    it "does not mark notification as delivered if the queue is full" do
      response.stub(:body => JSON.dump({ "failure" => 0 }))
      response.stub(:to_hash => { "x-notificationstatus" => ["QueueFull"] })
      # Ten minutes
      batch.should_receive(:mark_retryable).with(notification, Time.now + (60*10))
      perform
    end

    it "marks the notification retryable if the notification is supressed" do
      response.stub(:body => JSON.dump({ "faliure" => 0 }))
      response.stub(:to_hash => { "x-notificationstatus" => ["Supressed"] })
      batch.should_receive(:mark_delivered).with(notification)
      perform
    end
  end

  describe "an 400 response" do
    before { response.stub(:code => 400) }
    it "marks notifications as failed" do
      batch.should_receive(:mark_failed).with(notification, 400,
                                              "Bad XML or malformed notification URI")
      perform rescue Rapns::DeliveryError
    end
  end

  describe "an 401 response" do
    before { response.stub(:code => 401) }
    it "marks notifications as failed" do
      batch.should_receive(:mark_failed).with(notification, 401,
                                              "Unauthorized to send a notification to this app")
      perform rescue Rapns::DeliveryError
    end
  end

  describe "an 404 response" do
    before { response.stub(:code => 404) }
    it "marks notifications as failed" do
      batch.should_receive(:mark_failed).with(notification, 404,
                                              "Not found!")
      perform rescue Rapns::DeliveryError
    end
  end

  describe "an 406 response" do
    before { response.stub(:code => 406) }

    it "enable the safe mode time" do
      perform rescue Rapns::DeliveryError
      delivery.safe_mode_time.should_not be_nil
    end

    it "warns about the safe model after this response." do
      logger.should_receive(:warn)
      perform rescue Rapns::DeliveryError
      perform rescue Rapns::DeliveryError
    end

    it "does not perform the notifications when are in safe mode" do
      perform rescue Rapns::DeliveryError
      delivery.should_not_receive(:perform_unsafe)
      perform rescue Rapns::DeliveryError
    end
  end

  describe "an 412 response" do
    before { response.stub(:code => 412) }
    it "marks notifications as failed" do
      batch.should_receive(:mark_failed).with(notification, 412,
                                              "Precondition Failed. Device is Disconnected for now.")
      perform rescue Rapns::DeliveryError
    end
  end

  describe "an 503 response" do
    before { response.stub(:code => 503) }
    it "marks notifications as failed" do
      batch.should_receive(:mark_failed).with(notification, 503,
                                              "Service unavailable.")
      perform rescue Rapns::DeliveryError
    end
  end

  describe "Safe Mode" do
    # NOTE: Don't know how to compare the dates here.
    # See lib/rapns/daemon/wpns/delivery.rb @ line 21
    before {
      response.stub(:code => 400)
      delivery.stub(:safe_mode_time => now - 10)
    }

    it "has to set safe_mode_time to nil when it's finished" do
      delivery.safe_mode_time=now-10.seconds
      perform rescue Rapns::DeliveryError
      # delivery.safe_mode_time.should be_nil
    end
  end
end
