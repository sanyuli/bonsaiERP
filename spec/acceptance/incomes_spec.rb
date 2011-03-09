# encoding: utf-8
# author: Boris Barroso
# email: boriscyber@gmail.com
require File.dirname(__FILE__) + '/acceptance_helper'

def income_params
    d = Date.today
    @income_params = {"active"=>nil, "bill_number"=>"56498797", "contact_id"=>1, 
      "currency_exchange_rate"=>1, "currency_id"=>1, "date"=>d, 
      "description"=>"Esto es una prueba", "discount"=>3, "project_id"=>1 
    }
    details = [
      { "description"=>"jejeje", "item_id"=>1, "organisation_id"=>1, "price"=>15.5, "quantity"=> 10},
      { "description"=>"jejeje", "item_id"=>2, "organisation_id"=>1, "price"=>10, "quantity"=> 20}
    ]
    @income_params[:transaction_details_attributes] = details
    @income_params
end

def pay_plan_params(options)
  d = options[:payment_date] || Date.today
  {:alert_date => (d - 5.days), :payment_date => d,
   :interests_penalties => 0,
   :ctype => 'Income', :description => 'Prueba de vida!', 
   :email => true }.merge(options)
end

feature "Income", "test features" do
  background do
    OrganisationSession.set(:id => 1, :name => 'ecuanime', :currency_id => 1)
    
    Bank.destroy_all()
    Bank.create!(:number => '123', :currency_id => 1, :name => 'Bank JE', :amount => 0) {|a| a.id = 1 }

    CashRegister.destroy_all()
    CashRegister.create!(:name => 'Cash register Bs.', :amount => 0, :currency_id => 1, :address => 'Uno') {|cr| cr.id = 2}

    Contact.destroy_all
    Contact.create!(:name => 'karina', :matchcode => 'karina', :address => 'Mallasa') {|c| c.id = 1 }
  end

  scenario "Create a payment with nearest pay_plan" do
    i = Income.new(income_params)

    i.save.should == true
    pp = i.create_pay_plan(pay_plan_params(:amount => 100))

    i = Income.find(i.id)
    i.pay_plans.unpaid.size.should == 2
    i.balance.should == i.pay_plans_total

    #i.pay_plans.unpaid.each{|pp| puts "#{pp.amount}"} ###

    # BANK payment
    p = i.new_payment(:account_id => 1, :reference => '54654654654', :date => Date.today, :amount => 100)
    p.class.should == Payment
    p.paid?.should == false

    p.amount.should == 100

    p.save.should == true
    p.state.should == 'conciliation'

    al1 = p.account_ledger

    i = Income.find(i.id)
  
    i.balance.should == i.total
    i.pay_plans.unpaid.size.should == 2

    # CASH payment
    p = i.new_payment(:account_id => 2, :reference => 'NA', :date => Date.today + 2.days)
    amt =  i.balance - 100
    p.amount.should == amt

    p.save.should == true

    p.state.should == 'paid'
    al2 = p.account_ledger #AccountLedger.find_by_payment_id(p.id)
    al2.class.should == AccountLedger
    al2.conciliation.should == true

    i = Income.find(i.id)
    i.balance.should_not == i.total

    al1.conciliate_account.should == true
    al1.conciliation.should == true

    p_id = al1.payment.id
    Payment.find(p_id).state.should == 'paid'

    i = Income.find(i.id)
    i.balance.should == 0
    i.pay_plans.unpaid.size.should == 0
  end

  scenario "Pay many pay_plans at the same time" do
    d = Date.today
    i = Income.new(income_params.merge(:date => d))
    
    i.save.should == true
    bal = i.balance

    pp = i.create_pay_plan(pay_plan_params(:amount => 100, :payment_date => d, :repeat => true))
    i = Income.find(i.id)
    #i.pay_plans.unpaid.each{|pp| puts "#{pp.amount} #{pp.payment_date}"} ###

    i.pay_plans.unpaid.size.should == 4
    i.pay_plans.unpaid[0].payment_date.should == d
    i.pay_plans.unpaid[0].alert_date.should == d - 5.days
    i.pay_plans.unpaid[1].payment_date.should == d + 1.month

    pdate = i.pay_plans.unpaid[1].payment_date
    adate =  i.pay_plans.unpaid[1].alert_date

    p = i.new_payment(:account_id => 2, :reference => 'NA', :date => d, :amount => 150)
    
    p.amount.should == 150
    p.save.should == true

    i = Income.find(i.id)
    i.pay_plans.unpaid.first.payment_date.should == d + 1.month

    i.balance.should == bal - 150
    i.balance.should == i.pay_plans_total
  end

end
