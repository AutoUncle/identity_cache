require "test_helper"

class FetchMultiTest < IdentityCache::TestCase
  def setup
    super
    @bob = Record.create!(:title => 'bob')
    @joe = Record.create!(:title => 'joe')
    @fred = Record.create!(:title => 'fred')
    @bob_blob_key = "IDC:blob:Record:#{cache_hash("created_at:datetime,id:integer,record_id:integer,title:string,updated_at:datetime")}:1"
    @joe_blob_key = "IDC:blob:Record:#{cache_hash("created_at:datetime,id:integer,record_id:integer,title:string,updated_at:datetime")}:2"
    @fred_blob_key = "IDC:blob:Record:#{cache_hash("created_at:datetime,id:integer,record_id:integer,title:string,updated_at:datetime")}:3"
    @tenth_blob_key = "IDC:blob:Record:#{cache_hash("created_at:datetime,id:integer,record_id:integer,title:string,updated_at:datetime")}:10"
  end

  def test_fetch_multi_with_no_records
    assert_equal [], Record.fetch_multi
  end

  def test_fetch_multi_with_all_hits
    cache_response = {}
    cache_response[@bob_blob_key] = @bob
    cache_response[@joe_blob_key] = @joe
    cache_response[@fred_blob_key] = @fred
    IdentityCache.cache.expects(:read_multi).with(@bob_blob_key, @joe_blob_key, @fred_blob_key).returns(cache_response)
    assert_equal [@bob, @joe, @fred], Record.fetch_multi(@bob.id, @joe.id, @fred.id)
  end

  def test_fetch_multi_with_all_misses
    cache_response = {}
    cache_response[@bob_blob_key] = nil
    cache_response[@joe_blob_key] = nil
    cache_response[@fred_blob_key] = nil
    IdentityCache.cache.expects(:read_multi).with(@bob_blob_key, @joe_blob_key, @fred_blob_key).returns(cache_response)
    assert_equal [@bob, @joe, @fred], Record.fetch_multi(@bob.id, @joe.id, @fred.id)
  end

  def test_fetch_multi_with_mixed_hits_and_misses
    cache_response = {}
    cache_response[@bob_blob_key] = @bob
    cache_response[@joe_blob_key] = nil
    cache_response[@fred_blob_key] = @fred
    IdentityCache.cache.expects(:read_multi).with(@bob_blob_key, @joe_blob_key, @fred_blob_key).returns(cache_response)
    assert_equal [@bob, @joe, @fred], Record.fetch_multi(@bob.id, @joe.id, @fred.id)
  end

  def test_fetch_multi_with_mixed_hits_and_misses_and_responses_in_the_wrong_order
    cache_response = {}
    cache_response[@bob_blob_key] = nil
    cache_response[@joe_blob_key] = nil
    cache_response[@fred_blob_key] = @fred
    IdentityCache.cache.expects(:read_multi).with(@bob_blob_key, @fred_blob_key, @joe_blob_key).returns(cache_response)
    assert_equal [@bob, @fred, @joe], Record.fetch_multi(@bob.id, @fred.id, @joe.id)
  end

  def test_fetch_multi_with_mixed_hits_and_misses_and_non_existant_keys_1
    populate_only_fred

    IdentityCache.cache.expects(:read_multi).with(@tenth_blob_key, @bob_blob_key, @joe_blob_key, @fred_blob_key).returns(@cache_response)
    assert_equal [@bob, @joe, @fred], Record.fetch_multi(10, @bob.id, @joe.id, @fred.id)
  end

  def test_fetch_multi_with_mixed_hits_and_misses_and_non_existant_keys_2
    populate_only_fred

    IdentityCache.cache.expects(:read_multi).with(@fred_blob_key, @bob_blob_key, @tenth_blob_key, @joe_blob_key).returns(@cache_response)
    assert_equal [@fred, @bob, @joe], Record.fetch_multi(@fred.id, @bob.id, 10, @joe.id)
  end


  def test_fetch_multi_works_with_nils
    cache_result = {1 => IdentityCache::CACHED_NIL, 2 => IdentityCache::CACHED_NIL}
    fetch_result = {1 => nil, 2 => nil}

    IdentityCache.cache.expects(:read_multi).with(1,2).times(2).returns({1 => nil, 2 => nil}, cache_result)
    IdentityCache.cache.expects(:write).with(1, IdentityCache::CACHED_NIL).once
    IdentityCache.cache.expects(:write).with(2, IdentityCache::CACHED_NIL).once

    results = IdentityCache.fetch_multi(1,2) do |keys|
      [nil, nil]
    end
    assert_equal fetch_result, results

    results = IdentityCache.fetch_multi(1,2) do |keys|
      flunk "Contents should have been fetched from cache successfully"
    end

    assert_equal fetch_result, results
  end

  def test_fetch_multi_duplicate_ids
    assert_equal [@joe, @bob, @joe], Record.fetch_multi(@joe.id, @bob.id, @joe.id)
  end

  def test_fetch_multi_with_open_transactions_hits_the_database
    Record.connection.expects(:open_transactions).at_least_once.returns(1)
    IdentityCache.cache.expects(:read_multi).never
    assert_equal [@bob, @joe, @fred], Record.fetch_multi(@bob.id, @joe.id, @fred.id)
  end

  def test_fetch_multi_with_open_transactions_returns_results_in_the_order_of_the_passed_ids
    Record.connection.expects(:open_transactions).at_least_once.returns(1)
    assert_equal [@joe, @bob, @fred], Record.fetch_multi(@joe.id, @bob.id, @fred.id)
  end

  def test_fetch_multi_with_duplicate_ids_in_transaction_returns_results_in_the_order_of_the_passed_ids
    Record.connection.expects(:open_transactions).at_least_once.returns(1)
    assert_equal [@joe, @bob, @joe], Record.fetch_multi(@joe.id, @bob.id, @joe.id)
  end

  def test_fetch_multi_includes_cached_associations
    Record.send(:cache_has_many, :associated_records, :embed => true)
    Record.send(:cache_has_one, :associated)
    Record.send(:cache_belongs_to, :record)

    cache_response = {}
    cache_response[@bob_blob_key] = nil
    cache_response[@joe_blob_key] = nil
    cache_response[@fred_blob_key] = nil

    IdentityCache.cache.expects(:read_multi).with(@bob_blob_key, @joe_blob_key, @fred_blob_key).returns(cache_response)

    mock_relation = mock("ActiveRecord::Relation")
    Record.expects(:where).returns(mock_relation)
    mock_relation.expects(:includes).with([:associated_records, :associated]).returns(stub(:all => [@bob, @joe, @fred]))
    assert_equal [@bob, @joe, @fred], Record.fetch_multi(@bob.id, @joe.id, @fred.id)
  end

  def test_fetch_multi_includes_cached_associations_and_other_asked_for_associations
    Record.send(:cache_has_many, :associated_records, :embed => true)
    Record.send(:cache_has_one, :associated)
    Record.send(:cache_belongs_to, :record)

    cache_response = {}
    cache_response[@bob_blob_key] = nil
    cache_response[@joe_blob_key] = nil
    cache_response[@fred_blob_key] = nil

    IdentityCache.cache.expects(:read_multi).with(@bob_blob_key, @joe_blob_key, @fred_blob_key).returns(cache_response)

    mock_relation = mock("ActiveRecord::Relation")
    Record.expects(:where).returns(mock_relation)
    mock_relation.expects(:includes).with([:associated_records, :associated, {:record => []}]).returns(stub(:all => [@bob, @joe, @fred]))
    assert_equal [@bob, @joe, @fred], Record.fetch_multi(@bob.id, @joe.id, @fred.id, {:includes => :record})
  end

  def test_fetch_multi_batch_fetches_non_embedded_first_level_has_many_associations
    Record.send(:cache_has_many, :associated_records, :embed => false)

    child_records = []
    [@bob, @joe].each do |parent|
      3.times do |i|
        child_records << (child_record = parent.associated_records.create!(:name => i.to_s))
        AssociatedRecord.fetch(child_record.id)
      end
    end

    Record.fetch_multi(@bob.id, @joe.id) # populate the cache entries and associated children ID variables

    assert_memcache_operations(2) do
      @cached_bob, @cached_joe = Record.fetch_multi(@bob.id, @joe.id, :includes => :associated_records)
      assert_equal child_records[0..2].sort, @cached_bob.fetch_associated_records.sort
      assert_equal child_records[3..5].sort, @cached_joe.fetch_associated_records.sort
    end
  end

  def test_fetch_multi_batch_fetches_first_level_belongs_to_associations
    AssociatedRecord.send(:cache_belongs_to, :record, :embed => false)

    @bob_child  = @bob.associated_records.create!(:name => "bob child")
    @fred_child = @fred.associated_records.create!(:name => "fred child")

    # populate the cache entries and associated children ID variables
    AssociatedRecord.fetch_multi(@bob_child.id, @fred_child.id)
    Record.fetch_multi(@bob.id, @fred.id)

    assert_memcache_operations(2) do
      @cached_bob_child, @cached_fred_child = AssociatedRecord.fetch_multi(@bob_child.id, @fred_child.id, :includes => :record)
      assert_equal @bob,  @cached_bob_child.fetch_record
      assert_equal @fred, @cached_fred_child.fetch_record
    end
  end

  def test_find_batch_coerces_ids_to_primary_key_type
    mock_relation = mock("ActiveRecord::Relation")
    Record.expects(:where).returns(mock_relation)
    mock_relation.expects(:includes).returns(stub(:all => [@bob, @joe, @fred]))

    Record.find_batch([@bob, @joe, @fred].map(&:id).map(&:to_s))
  end

  private

  def populate_only_fred
    @cache_response = {}
    @cache_response[@bob_blob_key] = nil
    @cache_response[@joe_blob_key] = nil
    @cache_response[@tenth_blob_key] = nil
    @cache_response[@fred_blob_key] = @fred
  end
end
