#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

require "spec_helper"

describe User::Connecting, type: :model do
  let(:aspect1) { alice.aspects.first }
  let(:aspect2) { alice.aspects.create(name: "other") }

  let(:person) { FactoryGirl.create(:person) }

  describe "disconnecting" do
    describe "#disconnected_by" do
      it "removes contact sharing flag" do
        expect(bob.contacts.find_by(person_id: alice.person.id)).to be_sharing
        bob.disconnected_by(alice.person)
        expect(bob.contacts.find_by(person_id: alice.person.id)).not_to be_sharing
      end

      it "removes contact if not receiving" do
        eve.contacts.create(person: alice.person)

        expect {
          eve.disconnected_by(alice.person)
        }.to change(eve.contacts(true), :count).by(-1)
      end

      it "does not remove contact if disconnect twice" do
        contact = bob.contact_for(alice.person)
        expect(contact).to be_receiving

        expect {
          bob.disconnected_by(alice.person)
          bob.disconnected_by(alice.person)
        }.not_to change(bob.contacts(true), :count)

        contact.reload
        expect(contact).not_to be_sharing
        expect(contact).to be_receiving
      end

      it "removes notitications" do
        skip # TODO

        alice.share_with(eve.person, alice.aspects.first)
        expect(Notifications::StartedSharing.where(recipient_id: eve.id).first).not_to be_nil
        eve.disconnected_by(alice.person)
        expect(Notifications::StartedSharing.where(recipient_id: eve.id).first).to be_nil
      end
    end

    describe "#disconnect" do
      it "removes a contacts receiving flag" do
        expect(bob.contacts.find_by(person_id: alice.person.id)).to be_receiving
        bob.disconnect(bob.contact_for(alice.person))
        expect(bob.contacts(true).find_by(person_id: alice.person.id)).not_to be_receiving
      end

      it "removes contact if not sharing" do
        contact = alice.share_with(eve.person, alice.aspects.first)

        expect {
          alice.disconnect(contact)
        }.to change(alice.contacts(true), :count).by(-1)
      end

      it "does not remove contact if disconnect twice" do
        contact = bob.contact_for(alice.person)
        expect(contact).to be_sharing

        expect {
          alice.disconnect(contact)
          alice.disconnect(contact)
        }.not_to change(bob.contacts(true), :count)

        contact.reload
        expect(contact).not_to be_receiving
        expect(contact).to be_sharing
      end

      it "dispatches a retraction" do
        skip # TODO

        bob.disconnect bob.contact_for(eve.person)
      end

      it "should remove the contact from all aspects they are in" do
        contact = alice.contact_for(bob.person)
        alice.add_contact_to_aspect(contact, aspect2)

        expect {
          alice.disconnect(contact)
        }.to change(contact.aspects(true), :count).from(2).to(0)
      end
    end
  end

  describe "#share_with" do
    it "finds or creates a contact" do
      expect {
        alice.share_with(eve.person, alice.aspects.first)
      }.to change(alice.contacts, :count).by(1)
    end

    it "does not set mutual on intial share request" do
      alice.share_with(eve.person, alice.aspects.first)
      expect(alice.contacts.find_by(person_id: eve.person.id)).not_to be_mutual
    end

    it "does set mutual on share-back request" do
      eve.share_with(alice.person, eve.aspects.first)
      alice.share_with(eve.person, alice.aspects.first)

      expect(alice.contacts.find_by(person_id: eve.person.id)).to be_mutual
    end

    it "adds a contact to an aspect" do
      contact = alice.contacts.create(person: eve.person)
      allow(alice.contacts).to receive(:find_or_initialize_by).and_return(contact)

      expect {
        alice.share_with(eve.person, alice.aspects.first)
      }.to change(contact.aspects, :count).by(1)
    end

    context "dispatching" do
      it "dispatches a request on initial request" do
        contact = alice.contacts.new(person: eve.person)
        expect(alice.contacts).to receive(:find_or_initialize_by).and_return(contact)

        allow(Diaspora::Federation::Dispatcher).to receive(:defer_dispatch)
        expect(Diaspora::Federation::Dispatcher).to receive(:defer_dispatch).with(alice, contact)

        alice.share_with(eve.person, alice.aspects.first)
      end

      it "dispatches a request on a share-back" do
        eve.share_with(alice.person, eve.aspects.first)

        contact = alice.contact_for(eve.person)
        expect(alice.contacts).to receive(:find_or_initialize_by).and_return(contact)

        allow(Diaspora::Federation::Dispatcher).to receive(:defer_dispatch)
        expect(Diaspora::Federation::Dispatcher).to receive(:defer_dispatch).with(alice, contact)

        alice.share_with(eve.person, alice.aspects.first)
      end

      it "does not dispatch a request if contact already marked as receiving" do
        contact = alice.contacts.create(person: eve.person, receiving: true)
        allow(alice.contacts).to receive(:find_or_initialize_by).and_return(contact)

        allow(Diaspora::Federation::Dispatcher).to receive(:defer_dispatch).with(alice, instance_of(Profile))
        expect(Diaspora::Federation::Dispatcher).not_to receive(:defer_dispatch).with(alice, instance_of(Contact))

        alice.share_with(eve.person, aspect2)
      end

      it "posts profile" do
        allow(Diaspora::Federation::Dispatcher).to receive(:defer_dispatch)
        expect(Diaspora::Federation::Dispatcher).to receive(:defer_dispatch).with(alice, alice.profile)

        alice.share_with(eve.person, alice.aspects.first)
      end
    end

    it "sets receiving" do
      alice.share_with(eve.person, alice.aspects.first)
      expect(alice.contact_for(eve.person)).to be_receiving
    end

    it "should mark the corresponding notification as 'read'" do
      FactoryGirl.create(:notification, target: eve.person, recipient: alice, type: "Notifications::StartedSharing")
      expect(Notifications::StartedSharing.find_by(recipient_id: alice.id, target: eve.person).unread).to be_truthy

      alice.share_with(eve.person, aspect1)
      expect(Notifications::StartedSharing.find_by(recipient_id: alice.id, target: eve.person).unread).to be_falsey
    end
  end
end
