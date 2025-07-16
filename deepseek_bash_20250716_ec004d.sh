#!/bin/bash

# Laravel 12 E-Commerce Cart Setup Automation Script
# This script performs a complete installation and configuration

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if command succeeded
check_success() {
  if [ $? -ne 0 ]; then
    echo -e "${RED}Error: $1 failed${NC}"
    exit 1
  fi
}

# Step 1: Install Laravel 12
echo -e "${YELLOW}Step 1/12: Installing Laravel 12...${NC}"
composer create-project laravel/laravel ecommerce-cart
check_success "Laravel installation"
cd ecommerce-cart || exit

# Step 2: Environment Setup
echo -e "${YELLOW}Step 2/12: Setting up environment...${NC}"
cp .env.example .env
php artisan key:generate
check_success "Key generation"

# Update .env file with database config
echo -e "${YELLOW}Configuring database...${NC}"
sed -i 's/DB_CONNECTION=mysql/DB_CONNECTION=mysql/' .env
sed -i 's/DB_HOST=127.0.0.1/DB_HOST=127.0.0.1/' .env
sed -i 's/DB_PORT=3306/DB_PORT=3306/' .env
sed -i 's/DB_DATABASE=laravel/DB_DATABASE=laravel_cart/' .env
sed -i 's/DB_USERNAME=root/DB_USERNAME=root/' .env
sed -i 's/DB_PASSWORD=/DB_PASSWORD=/' .env

# Step 3: Database Setup
echo -e "${YELLOW}Step 3/12: Setting up database...${NC}"
php artisan migrate
check_success "Database migration"

# Step 4: Install Breeze for authentication
echo -e "${YELLOW}Step 4/12: Installing Laravel Breeze...${NC}"
composer require laravel/breeze --dev
php artisan breeze:install
php artisan migrate
npm install && npm run dev
check_success "Breeze installation"

# Step 5: Create Cart Model and Migration
echo -e "${YELLOW}Step 5/12: Creating cart model and migration...${NC}"
php artisan make:model CartItem -m

# Edit the migration file
cat > database/migrations/$(ls -t database/migrations | head -1) << 'EOL'
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

# Step 6: Create Product Model
echo -e "${YELLOW}Step 6/12: Creating product model...${NC}"
php artisan make:model Product -m

# Edit the product migration
cat > database/migrations/$(ls -t database/migrations | head -1) << 'EOL'
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

# Run migrations
echo -e "${YELLOW}Running migrations...${NC}"
php artisan migrate
check_success "Cart and product migrations"

# Step 7: Set Up Model Relationships
echo -e "${YELLOW}Step 7/12: Setting up model relationships...${NC}"

# Append to User model
cat >> app/Models/User.php << 'EOL'

    public function cartItems()
    {
        return $this->hasMany(CartItem::class);
    }
EOL

# Create CartItem model content
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

# Create Product model content
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

# Step 8: Create Cart Controller
echo -e "${YELLOW}Step 8/12: Creating cart controller...${NC}"
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

# Step 9: Set Up API Routes
echo -e "${YELLOW}Step 9/12: Setting up API routes...${NC}"
cat >> routes/api.php << 'EOL'

use App\Http\Controllers\Api\CartController;

Route::middleware('auth:sanctum')->group(function () {
    Route::post('/cart/sync', [CartController::class, 'sync']);
    Route::get('/cart', [CartController::class, 'get']);
});
EOL

# Step 10: Install Sanctum
echo -e "${YELLOW}Step 10/12: Installing Laravel Sanctum...${NC}"
composer require laravel/sanctum
php artisan vendor:publish --provider="Laravel\Sanctum\SanctumServiceProvider"
php artisan migrate
check_success "Sanctum installation"

# Step 11: Create Sample Products
echo -e "${YELLOW}Step 11/12: Creating sample products...${NC}"
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
EOL

php artisan db:seed --class=ProductsTableSeeder
check_success "Product seeding"

# Step 12: Implement Cleanup Command
echo -e "${YELLOW}Step 12/12: Creating cart cleanup command...${NC}"
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

# Update Kernel.php
sed -i '/protected \$commands = \[/a \        \\App\\Console\\Commands\\CleanExpiredCarts::class,' app/Console/Kernel.php

sed -i '/protected function schedule(Schedule \$schedule)/a \        \$schedule->command('\''carts:clean'\'')->daily();' app/Console/Kernel.php

# Final steps
echo -e "${GREEN}Setup completed successfully!${NC}"
echo -e "${YELLOW}Here are the next steps:${NC}"
echo "1. Create a user by visiting /register"
echo "2. Use the following API endpoints:"
echo "   - POST /api/cart/sync (with auth token)"
echo "   - GET /api/cart (with auth token)"
echo "3. The cart cleanup will run daily automatically"

# Start the development server (optional)
echo -e "${YELLOW}Would you like to start the development server? (y/n)${NC}"
read -r answer
if [ "$answer" != "${answer#[Yy]}" ] ;then
    php artisan serve
fi