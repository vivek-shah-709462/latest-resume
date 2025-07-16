#!/bin/bash

# Laravel 12 E-Commerce Cart Setup Automation Script (Idempotent Version)
# This script can be safely re-run and will pick up where it left off

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if required commands are available
check_requirements() {
  local missing=()
  
  # Check PHP
  if ! command -v php &> /dev/null; then
    missing+=("PHP")
  fi
  
  # Check Composer
  if ! command -v composer &> /dev/null; then
    missing+=("Composer")
  fi
  
  # Check MySQL client
  if ! command -v mysql &> /dev/null; then
    missing+=("MySQL client")
  fi
  
  if [ ${#missing[@]} -ne 0 ]; then
    echo -e "${RED}Error: Missing required components:${NC}"
    for item in "${missing[@]}"; do
      echo " - $item"
    done
    exit 1
  fi
}

# Function to check if command succeeded
check_success() {
  if [ $? -ne 0 ]; then
    echo -e "${RED}Error: $1 failed${NC}"
    echo -e "${YELLOW}You can re-run the script to continue where it left off.${NC}"
    exit 1
  fi
}

# Function to check if Laravel is already installed
check_laravel_installed() {
  if [ -f "artisan" ] && [ -d "vendor" ]; then
    return 0
  else
    return 1
  fi
}

# Function to check if step needs to be run
should_run_step() {
  local step_name=$1
  if [ ! -f ".setup_completed_$step_name" ]; then
    return 0
  else
    return 1
  fi
}

# Function to mark step as completed
mark_step_completed() {
  local step_name=$1
  touch ".setup_completed_$step_name"
}

# Main execution
main() {
  # Check requirements at start
  check_requirements

  # Step 1: Install Laravel 12 (only if not already installed)
  if should_run_step "install_laravel"; then
    echo -e "${YELLOW}Step 1/12: Installing Laravel 12...${NC}"
    if [ ! -d "ecommerce-cart" ]; then
      composer create-project laravel/laravel ecommerce-cart
      check_success "Laravel installation"
    fi
    cd ecommerce-cart || exit
    mark_step_completed "install_laravel"
  else
    echo -e "${GREEN}Step 1/12: Laravel already installed, skipping...${NC}"
    cd ecommerce-cart || exit
  fi

  # Step 2: Environment Setup
  if should_run_step "env_setup"; then
    echo -e "${YELLOW}Step 2/12: Setting up environment...${NC}"
    if [ ! -f ".env" ]; then
      cp .env.example .env
    fi
    
    if ! grep -q "APP_KEY=base64" .env; then
      php artisan key:generate
      check_success "Key generation"
    fi

    # Update .env file with database config
    echo -e "${YELLOW}Configuring database...${NC}"
    sed -i 's/DB_CONNECTION=mysql/DB_CONNECTION=mysql/' .env
    sed -i 's/DB_HOST=127.0.0.1/DB_HOST=127.0.0.1/' .env
    sed -i 's/DB_PORT=3306/DB_PORT=3306/' .env
    sed -i 's/DB_DATABASE=laravel/DB_DATABASE=laravel_cart/' .env
    sed -i 's/DB_USERNAME=root/DB_USERNAME=root/' .env
    sed -i 's/DB_PASSWORD=/DB_PASSWORD=/' .env
    
    mark_step_completed "env_setup"
  else
    echo -e "${GREEN}Step 2/12: Environment already setup, skipping...${NC}"
  fi

  # Step 3: Database Setup (only if migrations haven't run)
  if should_run_step "initial_migrations"; then
    echo -e "${YELLOW}Step 3/12: Setting up database...${NC}"
    if ! php artisan migrate:status | grep -q "Ran"; then
      php artisan migrate
      check_success "Database migration"
    fi
    mark_step_completed "initial_migrations"
  else
    echo -e "${GREEN}Step 3/12: Database already setup, skipping...${NC}"
  fi

  # Step 4: Install Breeze for authentication (only if not installed)
  if should_run_step "install_breeze"; then
    echo -e "${YELLOW}Step 4/12: Installing Laravel Breeze...${NC}"
    if ! composer show laravel/breeze &> /dev/null; then
      composer require laravel/breeze --dev
      php artisan breeze:install
      php artisan migrate
      mark_step_completed "install_breeze"
      
      # Handle Node/NPM installation separately with error recovery
      if command -v npm &> /dev/null; then
        echo -e "${YELLOW}Installing Node dependencies...${NC}"
        npm install && npm run dev
        check_success "Frontend assets compilation"
      else
        echo -e "${RED}Warning: npm not found. Frontend assets not compiled.${NC}"
        echo -e "${YELLOW}You can install Node.js and run 'npm install && npm run dev' later.${NC}"
      fi
    fi
  else
    echo -e "${GREEN}Step 4/12: Breeze already installed, skipping...${NC}"
  fi

  # Step 5: Create Cart Model and Migration (only if not exists)
  if should_run_step "cart_migration"; then
    echo -e "${YELLOW}Step 5/12: Creating cart model and migration...${NC}"
    if [ ! -f "app/Models/CartItem.php" ]; then
      php artisan make:model CartItem -m
      
      # Edit the migration file
      latest_migration=$(ls -t database/migrations/*_create_cart_items_table.php | head -1)
      if [ -z "$latest_migration" ]; then
        latest_migration="database/migrations/$(date +%Y_%m_%d_%H%M%S)_create_cart_items_table.php"
        touch "$latest_migration"
      fi
      
      cat > "$latest_migration" << 'EOL'
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up()
    {
        Schema::create('cart_items', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignId('product_id')->constrained()->cascadeOnDelete();
            $table->integer('quantity')->default(1);
            $table->timestamp('expires_at');
            $table->timestamps();
        });
    }

    public function down()
    {
        Schema::dropIfExists('cart_items');
    }
};
EOL
    fi
    mark_step_completed "cart_migration"
  else
    echo -e "${GREEN}Step 5/12: Cart model already exists, skipping...${NC}"
  fi

  # Step 6: Create Product Model (only if not exists)
  if should_run_step "product_migration"; then
    echo -e "${YELLOW}Step 6/12: Creating product model...${NC}"
    if [ ! -f "app/Models/Product.php" ]; then
      php artisan make:model Product -m
      
      # Edit the product migration
      latest_migration=$(ls -t database/migrations/*_create_products_table.php | head -1)
      if [ -z "$latest_migration" ]; then
        latest_migration="database/migrations/$(date +%Y_%m_%d_%H%M%S)_create_products_table.php"
        touch "$latest_migration"
      fi
      
      cat > "$latest_migration" << 'EOL'
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up()
    {
        Schema::create('products', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->decimal('price', 10, 2);
            $table->text('description')->nullable();
            $table->timestamps();
        });
    }

    public function down()
    {
        Schema::dropIfExists('products');
    }
};
EOL
    fi
    mark_step_completed "product_migration"
  else
    echo -e "${GREEN}Step 6/12: Product model already exists, skipping...${NC}"
  fi

  # Run pending migrations
  if should_run_step "run_migrations"; then
    echo -e "${YELLOW}Running pending migrations...${NC}"
    php artisan migrate
    check_success "Migrations"
    mark_step_completed "run_migrations"
  else
    echo -e "${GREEN}Migrations already run, skipping...${NC}"
  fi

  # Step 7: Set Up Model Relationships (idempotent)
  if should_run_step "model_relationships"; then
    echo -e "${YELLOW}Step 7/12: Setting up model relationships...${NC}"
    
    # User model - only add if not present
    if ! grep -q "cartItems()" app/Models/User.php; then
      cat >> app/Models/User.php << 'EOL'

    public function cartItems()
    {
        return $this->hasMany(CartItem::class);
    }
EOL
    fi
    
    # Create CartItem model if not exists
    if [ ! -f "app/Models/CartItem.php" ]; then
      cat > app/Models/CartItem.php << 'EOL'
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class CartItem extends Model
{
    use HasFactory;

    protected $fillable = ['user_id', 'product_id', 'quantity', 'expires_at'];

    protected $casts = [
        'expires_at' => 'datetime',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function product()
    {
        return $this->belongsTo(Product::class);
    }
}
EOL
    fi
    
    # Create Product model if not exists
    if [ ! -f "app/Models/Product.php" ]; then
      cat > app/Models/Product.php << 'EOL'
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Product extends Model
{
    use HasFactory;

    protected $fillable = ['name', 'price', 'description'];
}
EOL
    fi
    
    mark_step_completed "model_relationships"
  else
    echo -e "${GREEN}Step 7/12: Model relationships already setup, skipping...${NC}"
  fi

  # Step 8: Create Cart Controller (only if not exists)
  if should_run_step "cart_controller"; then
    echo -e "${YELLOW}Step 8/12: Creating cart controller...${NC}"
    if [ ! -f "app/Http/Controllers/Api/CartController.php" ]; then
      mkdir -p app/Http/Controllers/Api
      php artisan make:controller Api/CartController
      
      cat > app/Http/Controllers/Api/CartController.php << 'EOL'
<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CartItem;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

class CartController extends Controller
{
    public function sync(Request \$request)
    {
        \$validated = \$request->validate([
            'items' => 'required|array',
            'items.*.product_id' => 'required|integer|exists:products,id',
            'items.*.quantity' => 'required|integer|min:1'
        ]);
        
        \$user = \$request->user();
        
        // Delete existing cart items
        \$user->cartItems()->delete();
        
        // Create new items
        foreach (\$validated['items'] as \$item) {
            \$user->cartItems()->create([
                'product_id' => \$item['product_id'],
                'quantity' => \$item['quantity'],
                'expires_at' => Carbon::now()->addDays(30)
            ]);
        }
        
        return response()->json(['message' => 'Cart synced']);
    }
    
    public function get(Request \$request)
    {
        \$cartItems = \$request->user()
            ->cartItems()
            ->with('product:id,name,price')
            ->get();
            
        return response()->json([
            'items' => \$cartItems->map(function (\$item) {
                return [
                    'product_id' => \$item->product_id,
                    'quantity' => \$item->quantity,
                    'name' => \$item->product->name,
                    'price' => \$item->product->price,
                    'total' => \$item->product->price * \$item->quantity
                ];
            })
        ]);
    }
}
EOL
    fi
    mark_step_completed "cart_controller"
  else
    echo -e "${GREEN}Step 8/12: Cart controller already exists, skipping...${NC}"
  fi

  # Step 9: Set Up API Routes (idempotent)
  if should_run_step "api_routes"; then
    echo -e "${YELLOW}Step 9/12: Setting up API routes...${NC}"
    if ! grep -q "CartController" routes/api.php; then
      cat >> routes/api.php << 'EOL'

use App\Http\Controllers\Api\CartController;

Route::middleware('auth:sanctum')->group(function () {
    Route::post('/cart/sync', [CartController::class, 'sync']);
    Route::get('/cart', [CartController::class, 'get']);
});
EOL
    fi
    mark_step_completed "api_routes"
  else
    echo -e "${GREEN}Step 9/12: API routes already setup, skipping...${NC}"
  fi

  # Step 10: Install Sanctum (only if not installed)
  if should_run_step "install_sanctum"; then
    echo -e "${YELLOW}Step 10/12: Installing Laravel Sanctum...${NC}"
    if ! composer show laravel/sanctum &> /dev/null; then
      composer require laravel/sanctum
      php artisan vendor:publish --provider="Laravel\Sanctum\SanctumServiceProvider"
      php artisan migrate
      check_success "Sanctum installation"
    fi
    mark_step_completed "install_sanctum"
  else
    echo -e "${GREEN}Step 10/12: Sanctum already installed, skipping...${NC}"
  fi

  # Step 11: Create Sample Products (only if not exists)
  if should_run_step "seed_products"; then
    echo -e "${YELLOW}Step 11/12: Creating sample products...${NC}"
    if [ ! -f "database/seeders/ProductsTableSeeder.php" ]; then
      php artisan make:seeder ProductsTableSeeder
      
      cat > database/seeders/ProductsTableSeeder.php << 'EOL'
<?php

namespace Database\Seeders;

use App\Models\Product;
use Illuminate\Database\Seeder;

class ProductsTableSeeder extends Seeder
{
    public function run()
    {
        if (Product::count() === 0) {
            Product::create([
                'name' => 'Sample Product 1',
                'price' => 19.99,
                'description' => 'This is a sample product'
            ]);
            
            Product::create([
                'name' => 'Sample Product 2',
                'price' => 29.99,
                'description' => 'Another sample product'
            ]);
        }
    }
}
EOL
      
      php artisan db:seed --class=ProductsTableSeeder
      check_success "Product seeding"
    fi
    mark_step_completed "seed_products"
  else
    echo -e "${GREEN}Step 11/12: Products already seeded, skipping...${NC}"
  fi

  # Step 12: Implement Cleanup Command (only if not exists)
  if should_run_step "cleanup_command"; then
    echo -e "${YELLOW}Step 12/12: Creating cart cleanup command...${NC}"
    if [ ! -f "app/Console/Commands/CleanExpiredCarts.php" ]; then
      php artisan make:command CleanExpiredCarts
      
      cat > app/Console/Commands/CleanExpiredCarts.php << 'EOL'
<?php

namespace App\Console\Commands;

use App\Models\CartItem;
use Illuminate\Console\Command;

class CleanExpiredCarts extends Command
{
    protected \$signature = 'carts:clean';

    protected \$description = 'Remove expired cart items';

    public function handle()
    {
        \$deleted = CartItem::where('expires_at', '<', now())->delete();
        \$this->info("Cleaned up {\$deleted} expired cart items.");
        return 0;
    }
}
EOL
      
      # Update Kernel.php (idempotent)
      if ! grep -q "CleanExpiredCarts" app/Console/Kernel.php; then
        sed -i '/protected \$commands = \[/a \        \\App\\Console\\Commands\\CleanExpiredCarts::class,' app/Console/Kernel.php
      fi
      
      if ! grep -q "carts:clean" app/Console/Kernel.php; then
        sed -i '/protected function schedule(Schedule \$schedule)/a \        \$schedule->command('\''carts:clean'\'')->daily();' app/Console/Kernel.php
      fi
    fi
    mark_step_completed "cleanup_command"
  else
    echo -e "${GREEN}Step 12/12: Cleanup command already exists, skipping...${NC}"
  fi

  # Final output
  echo -e "${GREEN}Setup completed successfully!${NC}"
  echo -e "${YELLOW}Here are the next steps:${NC}"
  echo "1. Create a user by visiting /register"
  echo "2. Use the following API endpoints:"
  echo "   - POST /api/cart/sync (with auth token)"
  echo "   - GET /api/cart (with auth token)"
  echo "3. The cart cleanup will run daily automatically"
  
  # Clean up completion markers if everything succeeded
  rm -f .setup_completed_*
}

# Run main function
main

# Start the development server (optional)
echo -e "${YELLOW}Would you like to start the development server? (y/n)${NC}"
read -r answer
if [ "$answer" != "${answer#[Yy]}" ] ;then
    php artisan serve
fi