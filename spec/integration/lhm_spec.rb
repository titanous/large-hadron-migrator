#
#  Copyright (c) 2011, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
#  Schmidt
#

require File.expand_path(File.dirname(__FILE__)) + '/integration_helper'

require 'lhm'

describe Lhm do
  include IntegrationHelper

  before(:each) { connect_master! }

  describe "changes" do
    before(:each) do
      table_create(:users)
    end

    it "should add a column" do
      Lhm.change_table(:users) do |t|
        t.add_column(:logins, "INT(12) DEFAULT '0'")
      end

      slave do
        table_read(:users).columns["logins"].must_equal({
          :type => "int(12)",
          :metadata => "DEFAULT '0'"
        })
      end
    end

    it "should copy all rows" do
      23.times { |n| execute("insert into users set reference = '#{ n }'") }

      Lhm.change_table(:users) do |t|
        t.add_column(:logins, "INT(12) DEFAULT '0'")
      end

      slave do
        count_all(:users).must_equal(23)
      end
    end

    it "should remove a column" do
      Lhm.change_table(:users) do |t|
        t.remove_column(:comment)
      end

      slave do
        table_read(:users).columns["comment"].must_equal nil
      end
    end

    it "should add an index" do
      Lhm.change_table(:users) do |t|
        t.add_index([:comment, :created_at])
      end

      slave do
        key?(:users, [:comment, :created_at]).must_equal(true)
      end
    end

    it "should add an index on a column with a reserved name" do
      Lhm.change_table(:users) do |t|
        t.add_index(:group)
      end

      slave do
        key?(:users, :group).must_equal(true)
      end
    end

    it "should add a unqiue index" do
      Lhm.change_table(:users) do |t|
        t.add_unique_index(:comment)
      end

      slave do
        key?(:users, :comment, :unique).must_equal(true)
      end
    end

    it "should remove an index" do
      Lhm.change_table(:users) do |t|
        t.remove_index([:username, :created_at])
      end

      slave do
        key?(:users, [:username, :created_at]).must_equal(false)
      end
    end

    it "should apply a ddl statement" do
      Lhm.change_table(:users) do |t|
        t.ddl("alter table %s add column flag tinyint(1)" % t.name)
      end

      slave do
        table_read(:users).columns["flag"].must_equal({
          :type => "tinyint(1)",
          :metadata => "DEFAULT NULL"
        })
      end
    end

    describe "parallel" do
      it "should perserve inserts during migration" do
        50.times { |n| execute("insert into users set reference = '#{ n }'") }

        insert = Thread.new do
          10.times do |n|
            execute("insert into users set reference = '#{ 100 + n }'")
            sleep(0.17)
          end
        end

        Lhm.change_table(:users, :stride => 10, :throttle => 97) do |t|
          t.add_column(:parallel, "INT(10) DEFAULT '0'")
        end

        insert.join

        slave do
          count_all(:users).must_equal(60)
        end
      end

      it "should perserve deletes during migration" do
        50.times { |n| execute("insert into users set reference = '#{ n }'") }

        delete = Thread.new do
          10.times do |n|
            execute("delete from users where id = '#{ n + 1 }'")
            sleep(0.17)
          end
        end

        Lhm.change_table(:users, :stride => 10, :throttle => 97) do |t|
          t.add_column(:parallel, "INT(10) DEFAULT '0'")
        end

        delete.join

        slave do
          count_all(:users).must_equal(40)
        end
      end
    end
  end
end
