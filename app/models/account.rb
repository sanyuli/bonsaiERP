# encoding: utf-8
# author: Boris Barroso
# email: boriscyber@gmail.com
class Account < ActiveRecord::Base

  include ActionView::Helpers::NumberHelper

  # callbacks
  before_create :set_amount

  attr_readonly  :initial_amount, :original_type

  # Relationships
  belongs_to :accountable, polymorphic: true

  has_many :account_ledgers
  has_many :account_balances

  # Transaction
  #has_many :incomes,  :class_name => "Transaction", :conditions => "transactions.type = 'Income'"
  #has_many :expenses, :class_name => "Transaction", :conditions => "transactions.type = 'Expense'"

  # validations
  validates_presence_of :currency, :name
  validates_numericality_of :amount
  validates_inclusion_of :currency, in: CURRENCIES.keys


  # scopes
  scope :money, where(:accountable_type => "MoneyStore")
  scope :bank, where(:original_type => "Bank")
  scope :cash, where(:original_type => "Cash")
  scope :contact, where(:accountable_type => "Contact")
  scope :client, where(:original_type => "Client")
  scope :supplier, where(:original_type => "Supplier")
  scope :staff, where(:original_type => "Staff")
  scope :contact_money, lambda {|*account_ids|
    s = self.scoped
    s.where( s.table[:accountable_type].eq('Contact')
      .and(s.table[:accountable_id].in(account_ids))
      .and(s.table[:amount].lt(0))
      .or(s.table[:accountable_type].eq('MoneyStore'))
    ).order("accountable_type")
  }
  scope :contact_money_buy, lambda{|account_ids|
    s = self.scoped
    s.where( 
      s.table[:accountable_type].eq('Contact')
      .and(s.table[:accountable_id].in(account_ids))
      .and(s.table[:amount].gt(0) )
      .or(s.table[:original_type].eq('Staff').and(s.table[:amount].gt(0)) )
      .or(s.table[:accountable_type].eq('MoneyStore'))
    ).order("accountable_type")
  }
  scope :to_pay, contact.where("amount < 0")
  scope :to_recieve, contact.where("amount > 0")

  def to_s
    if accountable_type === "Contact"
      "#{name} (#{number_with_delimiter(amount.abs)} #{currency})"
    else
      "#{name} (#{number_with_delimiter(amount)}  #{currency})"
    end
  end

  def is_money?
    accountable_type === "MoneyStore"
  end

  def is_contact?
    accountable_type === "Contact"
  end

  def amount_to_conciliate()
    amount + account_ledger_details.sum(:amount)
  end

  # Returns all the related aacount_ledgers
  def get_ledgers
    t = "account_ledgers"
    AccountLedger.where("#{t}.account_id=:ac_id OR #{t}.to_id=:ac_id",:ac_id => id).order("created_at DESC")
  end

  # Creates a Hash with the id as the base
  def self.to_hash(*args)
    args = [:name, :currency_id] if args.empty?
    l = lambda {|v| args.map {|val| [val, v.send(val)] } }
    Hash[ Account.money.map {|v| [v.id, Hash[l.call(v)] ]  } ]
  end

  def select_cur(cur_id)
    account_currencies.select {|ac| ac.currency_id == cur_id }.first
  end

  # Returns all account_ledgers for an account_id and to_id
  def self.get_ledgers(includes = [:account, :to])
    AccountLedger.includes(*includes)
    .where("account_ledgers.account_id = :id OR account_ledgers.to_id = :id", :id => id)
  end

  def self.contact_account(c_id, cur_id)
    Account.where(:accountable_id => c_id, :accountable_type => "Contact", :currency_id => cur_id).first || nil
  end

private
  def set_amount
    self.amount ||= 0.0
    self.initial_amount ||= self.amount
  end
end
