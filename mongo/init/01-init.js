const dbName = process.env.MONGO_INITDB_DATABASE || "app_main";
const appUser = process.env.MONGO_APP_USERNAME || "app_user";
const appPass = process.env.MONGO_APP_PASSWORD || "app_password";

db = db.getSiblingDB(dbName);

db.createUser({
  user: appUser,
  pwd: appPass,
  roles: [{ role: "readWrite", db: dbName }]
});
