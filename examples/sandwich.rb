#example of jobs


# It's a slow job, so we'll spawn 10 forks
# fork is enabled by default
job "sandwich.make", :childs => 10, :fork => true do |args|
  debug "Making a sandwich to #{args[:for]}"
  # very slow job
  id = 10
  { :id => id }
end

# This is as fast job and don't make memory leaks, so We'll not use fork
job "sandwich.sell", :fork => false do |args|
  debug "Selling the sandwich #{args[:id]} to #{args[:for]}"
  #client = Client.find_by_name(args[:for])
  #sandwich = Sandwich.find(args[:id])
  #sale = client.buy_sandwich sandwich
  sale = args[:for] == "Renan"
  if sale
    { :sale_id => 20 }
  else
    warn "Can't sell the sandwich to #{args[:for]} :("
    false
  end
end

# fast job but make memory leaks, so We'll use fork
job "sandwich.ingredients.recalcule", :childs => 3, :fork => true do |args|
  debug "Recalculating the ingredients of sandwich #{args[:id]} sold to #{args[:for]} in sale #{args[:sale_id]}"
  #Ingredients.recalcule_based_on_sale(args[:sale_id])
end

# Example of Normal Jobs
#   def make_sandwich_for(client_name)
#     Beanpicker.enqueue("sandwich.make", :for => client_name)
#   end
#   This will call the "sandwich.make" job and pass a hash with client_name on :for key

# Example of Chain Jobs
#   Beanpicker.enqueue(["sandwich.make", "sandwich.sell", "sandwich.ingredients.recalcule"], :for => "Renan")
#   This will call all the three jobs
#
#   Beanpicker.enqueue(["sandwich.make", "sandwich.sell", "sandwich.ingredients.recalcule"], :for => "Raphael")
#   This will call the two first jobs, but not the third. Raphael don't have money to buy a sandwich, so the
#     second job will return false and Beanpicker will break the chain
